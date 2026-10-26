import AndrofestProtocol
import Combine
import CryptoKit
import Darwin
import Foundation
import Network
import Security

@MainActor
final class BridgeClient: ObservableObject {
    @Published private(set) var status = "Preparing connection"
    @Published private(set) var connected = false
    @Published private(set) var requiresKeychainAccess = false
    @Published private(set) var peerName: String?
    @Published private(set) var invitation: PairingInvitation?
    @Published private(set) var receivedCount = 0
    @Published private(set) var lastNotificationTitle: String?
    let connectionMode = "ble"
    @Published private(set) var transportStatus = "Preparing direct connection"
    @Published private(set) var peerCapabilities: [String] = []
    var onConnected: (() -> Void)?
    var onNotification: ((WireEnvelope<NotificationPosted>) -> Void)?
    var onNotificationRemoved: ((String) -> Void)?
    var onFileControl: ((FileControl) -> Void)?
    var onCallAudio: ((Data) -> Void)?
    var onFileChunk: ((FileChunk) -> Void)?
    var onDisconnected: (() -> Void)?
    var onDeviceStatus: ((DeviceStatus) -> Void)?
    var onSharedText: ((SharedText) -> Void)?
    var onCommandResult: ((CommandResult) -> Void)?

    @discardableResult
    func sendCommand(_ command: DeviceCommand) throws -> String {
        guard connected, peerCapabilities.contains("device.commands") else {
            throw TransferFailure("Phone disconnected or app update required.")
        }
        let event = WireEnvelope(sourceDeviceId: deviceID, payload: command)
        sendFrame(try WireCodec.encode(event), generation: connectionID)
        return event.id
    }

    private let deviceID: String
    private let name: String
    private let persist: Bool
    private let trustStore: any PeerTrustStore
    private let loadTrust: @Sendable (String, Bool) throws -> TrustedPhone?
    private let makeLink: () -> any PeerLink
    private let linkAvailable: () -> Bool
    private var trusted: TrustedPhone?
    private var connection: NWConnection?
    private var connectionID = UUID()
    private var heartbeat: Task<Void, Never>?
    private var realtimeAudioRequested = false
    private var handshakeDeadline: Task<Void, Never>?
    private var lastReceived = Date()
    #if DEBUG
        private var timingProbeRan = false
        private var probeTimes: [(time: TimeInterval, measured: Bool)] = []
        private var probeRTTs: [Double] = []
        private var probeActive = false
    #endif
    private var seenNonces: [String: Int64] = [:]
    private var seenMessages = MessageReplayWindow()
    private var connectionNotice: String?
    private let activeTransport = "Bluetooth LE"
    private var peerLink: (any PeerLink)?
    private var notificationReceipts = NotificationDeliveryState()
    private var trustReadTask: Task<Void, Never>?
    private var trustGeneration = UUID()
    private var trustLoaded = false
    var transportEvent: String { peerLink?.diagnosticState ?? "none" }

    init(
        deviceID: String, name: String, persist: Bool = true,
        loadTrust: (@Sendable (String, Bool) throws -> TrustedPhone?)? = nil,
        trustStore: any PeerTrustStore = KeychainPeerTrustStore(),
        makeLink: @escaping () -> any PeerLink = { NearbyBleLink() },
        linkAvailable: @escaping () -> Bool = { NearbyBleLink.available }
    ) {
        self.deviceID = deviceID
        self.name = name
        self.persist = persist
        self.trustStore = trustStore
        self.loadTrust =
            loadTrust ?? { account, interaction in
                try trustStore.load(account: account, allowInteraction: interaction)
            }
        self.makeLink = makeLink
        self.linkAvailable = linkAvailable
        if persist { readSavedTrust(allowInteraction: false) } else { trustLoaded = true; renewInvitation() }
        #if DEBUG
            Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    guard let self else { return }
                    self.writeDiagnosticStatus()
                }
            }
        #endif
    }

    /// An interactive read happens only after a visible user action. A denied
    /// read is never treated as an absent record or replaced by a fresh QR.
    func readSavedTrust(allowInteraction: Bool = true) {
        guard persist, trustReadTask == nil else { return }
        let account = deviceID, generation = trustGeneration
        let loader = loadTrust
        status = "Opening saved pairing"
        transportStatus = status
        trustReadTask = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try loader(account, allowInteraction) }
            }.value
            guard let self, !Task.isCancelled, self.trustGeneration == generation else { return }
            self.trustReadTask = nil
            switch result {
            case .success(let peer):
                self.trustLoaded = true; self.requiresKeychainAccess = false
                self.trusted = peer; self.peerName = peer?.name
                if peer != nil { self.connectPeer() } else { self.renewInvitation() }
            case .failure:
                self.requiresKeychainAccess = true
                self.status = "Keychain access is required for saved pairing"
                self.transportStatus = "Pairing preserved · Allow pairing key access"
            }
        }
    }

    func sendFileControl(_ control: FileControl) throws {
        guard connected else { throw TransferFailure("Phone disconnected.") }
        let data: Data
        switch control {
        case .offer(let value): data = try WireCodec.encode(WireEnvelope(sourceDeviceId: deviceID, payload: value))
        case .accept(let value): data = try WireCodec.encode(WireEnvelope(sourceDeviceId: deviceID, payload: value))
        case .complete(let value): data = try WireCodec.encode(WireEnvelope(sourceDeviceId: deviceID, payload: value))
        case .cancel(let value): data = try WireCodec.encode(WireEnvelope(sourceDeviceId: deviceID, payload: value))
        }
        sendFrame(data, generation: connectionID)
    }

    func sendFileChunk(_ chunk: FileChunk) throws {
        guard connected else { throw TransferFailure("Phone disconnected.") }
        sendFrame(try chunk.encode(), generation: connectionID)
    }

    func sendCallAudio(_ payload: Data) async throws {
        guard connected, peerCapabilities.contains("call.audio"), let connection,
            (22...1940).contains(payload.count), payload.prefix(4) == Data("AAP1".utf8)
        else { throw TransferFailure("No audio connection") }
        let frame = try WireFrame.encode(payload)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: frame,
                completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
        }
    }

    func sendClipboardImage(_ png: Data, id: String) async throws {
        guard connected, peerCapabilities.contains("clipboard.image.receive"),
            png.count <= ClipboardImageChunk.maxImageBytes
        else { throw TransferFailure("Phone does not support image clipboard.") }
        let generation = connectionID
        let hash = Data(SHA256.hash(data: png))
        for offset in stride(from: 0, to: png.count, by: ClipboardImageChunk.maxChunkBytes) {
            try Task.checkCancellation()
            guard generation == connectionID, connected, let connection else {
                throw TransferFailure("Phone connection lost.")
            }
            let payload = try ClipboardImageChunk(
                id: id, offset: offset, total: png.count, sha256: hash,
                data: png.subdata(in: offset..<min(png.count, offset + ClipboardImageChunk.maxChunkBytes))
            ).encode()
            let frame = try WireFrame.encode(payload)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(
                    content: frame,
                    completion: .contentProcessed { error in
                        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                    })
            }
        }
    }

    func connectPeer() {
        if persist && !trustLoaded { readSavedTrust(); return }
        guard let candidate = trusted?.invitation ?? invitation else { return }
        guard linkAvailable() else { transportStatus = "This build does not include the Bluetooth helper."; return }
        guard peerLink?.isRunning != true else { return }
        let link = makeLink(); peerLink = link
        link.onStatus = { [weak self] in self?.transportStatus = $0 }
        link.onIntroduction = { [weak self] intro in self?.candidate(for: intro) != nil }
        link.onReady = { [weak self] port, intro in
            guard let self, !self.connected, let approved = self.candidate(for: intro),
                self.seenNonces[intro.nonce] == nil
            else { return }
            self.seenNonces = self.seenNonces.filter { $0.value > epochMilliseconds() - 90_000 }
            guard self.seenNonces.count < 128 else { return }
            self.seenNonces[intro.nonce] = intro.timestamp
            self.disconnect(preserveRelay: true)
            self.connect(host: "127.0.0.1", introduction: intro, invitation: approved, port: port)
        }
        link.onClosed = { [weak self] in
            guard let self else { return }
            self.transportStatus = "Retrying direct connection"
            self.disconnect()
        }
        link.start(invitation: candidate)
    }

    private func candidate(for intro: PairingIntroduction) -> PairingInvitation? {
        let candidate: PairingInvitation
        if let trusted {
            guard trusted.deviceID == intro.deviceId, trusted.fingerprint == intro.fingerprint else { return nil }
            candidate = trusted.invitation
        } else {
            guard let invitation, invitation.expiresAt > epochMilliseconds() else {
                transportStatus = "QR code expired · Generate a new code"; return nil
            }
            candidate = invitation
        }
        return intro.verify(invitation: candidate) ? candidate : nil
    }

    func renewInvitation() {
        // A connected or saved association is never silently replaced by a QR.
        guard trusted == nil, trustLoaded else { return }
        disconnect()
        peerLink?.stop(); peerLink = nil
        let candidate = PairingInvitation(deviceId: deviceID, name: name)
        do {
            try candidate.validate()
            invitation = candidate
            seenNonces.removeAll()
            status = "Scan the QR code on your phone"
            connectPeer()
        } catch { status = "Could not create a pairing code." }
    }

    func forget() {
        trustGeneration = UUID(); trustReadTask?.cancel(); trustReadTask = nil
        do {
            if persist { try trustStore.remove(account: deviceID) }
            peerLink?.stop(); peerLink = nil
            trusted = nil; invitation = nil; peerName = nil; trustLoaded = true; requiresKeychainAccess = false
            disconnect()
            renewInvitation()
        } catch { status = error.localizedDescription }
    }

    func shutdown() {
        trustGeneration = UUID()
        trustReadTask?.cancel()
        trustReadTask = nil
        disconnect(preserveRelay: true)
        peerLink?.stop(); peerLink = nil
    }

    private func connect(
        host: NWEndpoint.Host, introduction: PairingIntroduction, invitation: PairingInvitation,
        port: UInt16
    ) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        CertificatePinning.configure(tls, fingerprint: introduction.fingerprint)
        let tcp = NWProtocolTCP.Options(); tcp.noDelay = true
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = true
        let client = NWConnection(host: host, port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        self.connection = client
        connectionNotice = nil
        let generation = UUID()
        connectionID = generation
        status = "\(introduction.name) verifying identity"
        handshakeDeadline = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.connectionID == generation, !self.connected else { return }
            self.disconnect()
        }
        client.stateUpdateHandler = { [weak self, weak client] state in
            Task { @MainActor in
                guard let self, self.connectionID == generation else { return }
                switch state {
                case .ready:
                    self.connectionNotice = nil
                    #if DEBUG
                        NSLog("Twinvia TLS: connection ready")
                    #endif
                    do {
                        self.sendFrame(
                            try JSONEncoder().encode(SessionAuthentication(invitation: invitation)),
                            generation: generation)
                        self.receiveFrame(generation: generation, introduction: introduction, invitation: invitation)
                    } catch { self.disconnect() }
                case .failed(let error):
                    #if DEBUG
                        NSLog("Twinvia TLS: connection failed: %@", String(describing: error))
                    #endif
                    self.disconnect()
                case .cancelled: self.disconnect()
                case .waiting(let error):
                    if client?.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        self.connectionNotice =
                            "Enable Twinvia in System Settings → Privacy & Security → Local Network on Mac."
                        self.status = self.connectionNotice!
                    }
                    #if DEBUG
                        NSLog("Twinvia TLS: waiting: %@", String(describing: error))
                    #endif
                default: break
                }
            }
        }
        client.start(queue: .main)
    }

    #if DEBUG
        private func runTimingProbe(generation: UUID) {
            timingProbeRan = true; probeRTTs = []
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Let initial phone-data synchronization finish before measuring.
                try? await Task.sleep(for: .seconds(10))
                guard self.connectionID == generation, self.connected else { return }
                self.probeActive = true
                self.setRealtimeAudio(self.realtimeAudioRequested)
                var sent = 0
                for _ in 0..<300 {
                    guard self.connectionID == generation, self.connected else { break }
                    self.sendPing(generation: generation, measured: true)
                    sent += 1
                    try? await Task.sleep(for: .milliseconds(20))
                }
                try? await Task.sleep(for: .seconds(2))
                guard self.connectionID == generation else { return }
                self.probeActive = false
                self.setRealtimeAudio(self.realtimeAudioRequested)
                let sorted = self.probeRTTs.sorted()
                let stats: [String: Any] = [
                    "sent": sent, "received": sorted.count,
                    "p50Ms": sorted.isEmpty ? -1 : sorted[sorted.count / 2],
                    "p95Ms": sorted.isEmpty ? -1 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))],
                    "maxMs": sorted.last ?? -1, "transport": "BLE + pinned TLS", "audioRequested": false,
                    "warmupSeconds": 10, "sampleIntervalMs": 20, "interactiveVoiceQoS": true, "rttMs": self.probeRTTs,
                ]
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("dev.androfest.macos")
                if let data = try? JSONSerialization.data(withJSONObject: stats) {
                    try? data.write(
                        to: directory.appendingPathComponent("transport-timing-test.json"), options: .atomic)
                }
            }
        }
    #endif

    func setRealtimeAudio(_ enabled: Bool) {
        realtimeAudioRequested = enabled
        #if DEBUG
            peerLink?.setRealtimeAudio(enabled || probeActive)
        #else
            peerLink?.setRealtimeAudio(enabled)
        #endif
    }

    private func sendPing(generation: UUID, measured: Bool = false) {
        guard generation == connectionID, connected else { return }
        #if DEBUG
            // All ping replies are ordered, including heartbeats during a probe.
            probeTimes.append((ProcessInfo.processInfo.systemUptime, measured))
        #endif
        sendFrame(Data("{\"kind\":\"session.ping\"}".utf8), generation: generation)
    }

    private func sendFrame(_ payload: Data, generation: UUID) {
        guard generation == connectionID, let connection, payload.count > 0, payload.count <= WireCodec.maxMessageBytes
        else { return }
        guard let frame = try? WireFrame.encode(payload) else { return }
        connection.send(
            content: frame,
            completion: .contentProcessed { [weak self] error in
                if error != nil { Task { @MainActor in if self?.connectionID == generation { self?.disconnect() } } }
            })
    }

    private func receiveFrame(generation: UUID, introduction: PairingIntroduction, invitation: PairingInvitation) {
        receiveExactly(4, generation: generation) { [weak self] header in
            guard let self else { return }
            guard let length = try? WireFrame.payloadLength(header) else { self.disconnect(); return }
            self.receiveExactly(length, generation: generation) { [weak self] payload in
                guard let self else { return }
                do {
                    try self.handleFrame(
                        payload, introduction: introduction, invitation: invitation, generation: generation)
                    if self.connectionID == generation {
                        self.receiveFrame(generation: generation, introduction: introduction, invitation: invitation)
                    }
                } catch { self.disconnect() }
            }
        }
    }

    private func receiveExactly(
        _ length: Int, generation: UUID, accumulated: Data = Data(),
        completion: @escaping @MainActor @Sendable (Data) -> Void
    ) {
        guard generation == connectionID, let connection else { return }
        let remaining = length - accumulated.count
        connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) {
            [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self, self.connectionID == generation else { return }
                var buffer = accumulated
                if let data { buffer.append(data) }
                if buffer.count == length {
                    completion(buffer)
                } else if error != nil || isComplete {
                    self.disconnect()
                } else {
                    self.receiveExactly(length, generation: generation, accumulated: buffer, completion: completion)
                }
            }
        }
    }

    private func handleFrame(
        _ data: Data, introduction: PairingIntroduction, invitation: PairingInvitation, generation: UUID
    ) throws {
        if connected && data == Data("{\"kind\":\"session.pong\"}".utf8) {
            lastReceived = Date()
            #if DEBUG
                if !probeTimes.isEmpty {
                    let ping = probeTimes.removeFirst()
                    if probeActive, ping.measured {
                        probeRTTs.append((ProcessInfo.processInfo.systemUptime - ping.time) * 1000)
                    }
                }
            #endif
            return
        }
        if connected && data.prefix(4) == Data("AAP1".utf8) {
            lastReceived = Date(); onCallAudio?(data); return
        }
        if connected && data.prefix(4) == Data("AFC1".utf8) {
            lastReceived = Date()
            onFileChunk?(try FileChunk.decode(data))
            return
        }
        let header = try JSONDecoder().decode(BridgeEvent.Header.self, from: data)
        guard header.sourceDeviceId == introduction.deviceId else { throw ProtocolError.invalidEnvelope }
        if !connected {
            let hello = try WireCodec.decode(DeviceHello.self, from: data)
            guard hello.payload.platform == "android" else { throw ProtocolError.invalidPayload }
            // Re-check the active QR/trust immediately before committing trust.
            guard candidate(for: introduction)?.id == invitation.id else { throw ProtocolError.invalidPayload }
            let peer = TrustedPhone(
                invitation: invitation, deviceID: introduction.deviceId, name: hello.payload.name,
                fingerprint: introduction.fingerprint)
            if persist && trusted == nil { try trustStore.save(peer, account: deviceID) }
            trusted = peer
            self.invitation = nil
            peerName = peer.name
            peerCapabilities = hello.payload.capabilities
            connected = true
            onConnected?()
            #if DEBUG
                NSLog("Twinvia authenticated transport: %@", activeTransport)
            #endif
            status = "\(peer.name) connected · Encrypted \(activeTransport)"
            transportStatus = "Bluetooth LE active · No shared network needed"
            handshakeDeadline?.cancel()
            lastReceived = Date()
            heartbeat = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    guard let self, self.connectionID == generation else { return }
                    if Date().timeIntervalSince(self.lastReceived) > 120 { self.disconnect(); return }
                    self.sendPing(generation: generation)
                }
            }
            #if DEBUG
                if CommandLine.arguments.contains("--transport-timing-test"), !timingProbeRan {
                    runTimingProbe(generation: generation)
                }
            #endif
            return
        }
        lastReceived = Date()
        guard seenMessages.insert(header.id) else { return }
        switch try BridgeEvent.decode(data) {
        case .notification(let message):
            #if DEBUG
                if message.payload.packageName == "dev.androfest.android"
                    && message.payload.key == "androfest-connection-test"
                {
                    NSLog("Twinvia synthetic notification received over: %@", activeTransport)
                }
            #endif
            if notificationReceipts.record(message.payload).changed { receivedCount += 1 }
            lastNotificationTitle = message.payload.title
            onNotification?(message)
        case .notificationRemoved(let key):
            notificationReceipts.remove(key); onNotificationRemoved?(key)
        case .file(let control): onFileControl?(control)
        case .deviceStatus(let status): onDeviceStatus?(status)
        case .sharedText(let text): onSharedText?(text)
        case .commandResult(let result): onCommandResult?(result)
        }
    }

    private func disconnect(preserveRelay: Bool = false) {
        if !preserveRelay { peerLink?.retryEndpoint() }
        connectionID = UUID()
        let previous = connection
        connection = nil
        previous?.cancel()
        heartbeat?.cancel()
        #if DEBUG
            probeTimes = []; probeActive = false
        #endif
        setRealtimeAudio(false)
        handshakeDeadline?.cancel()
        connected = false
        peerCapabilities = []
        onDisconnected?()
        status =
            connectionNotice ?? (trusted == nil ? "Scan the QR code on your phone" : "Waiting for phone connection")
    }

    #if DEBUG
        private func writeDiagnosticStatus() {
            guard persist else { return }
            // No pairing keys, identifiers, addresses or notification content.
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.androfest.macos")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let record: [String: Any] = [
                "connected": connected, "mode": connectionMode,
                "transport": activeTransport, "transportStatus": transportStatus,
                "nativeEvent": peerLink?.diagnosticState ?? "none", "receivedCount": receivedCount,
                "notifications": NotificationPresenter.diagnostics,
                "updatedAt": epochMilliseconds(),
            ]
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("connection-status.json"), options: .atomic)
            }
        }
    #endif

}
