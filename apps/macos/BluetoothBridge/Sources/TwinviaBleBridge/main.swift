import AppKit
import Darwin
import Foundation
import Network
import TwinviaProtocol
import NearbyConnections

/// Ordinary-permission BLE transport process. App authentication remains pinned TLS.
final class BleBridge: NSObject, AdvertiserDelegate, ConnectionManagerDelegate {
    var invitation: PairingInvitation?
    var manager: ConnectionManager?
    var advertiser: Advertiser?
    var peer: EndpointID?
    var introduction: PairingIntroduction?
    var listener: NWListener?
    var local: NWConnection?
    var acceptedLocal = false
    var generation = UUID()
    var transmitSequence: UInt32 = 0
    var receiveSequence: UInt32 = 0
    var waitingAck: UInt32?
    var receiving = false
    var pendingInbound: NearbyBleProtocol.Packet?
    var ackDeadline: DispatchWorkItem?
    var sessionDeadline: DispatchWorkItem?
    var stdinBuffer = Data()
    var attempts: [TimeInterval] = []
    var stopped = false
    var bytesIn: UInt64 = 0
    var bytesOut: UInt64 = 0

    func emit(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields; record["event"] = event
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
        }
    }
    func input(_ data: Data) {
        guard !stopped else { return }
        if data.isEmpty { stop(); return }
        stdinBuffer.append(data)
        guard stdinBuffer.count <= 8192 else { stop(); return }
        while let end = stdinBuffer.firstIndex(of: 10) {
            let bytes = stdinBuffer[..<end]; stdinBuffer.removeSubrange(...end)
            guard let record = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                let command = record["command"] as? String
            else { stop(); return }
            switch command {
            case "configure":
                guard manager == nil, let object = record["invitation"],
                    let encoded = try? JSONSerialization.data(withJSONObject: object),
                    let value = try? JSONDecoder().decode(PairingInvitation.self, from: encoded)
                else { stop(); return }
                do { try value.validate(allowExpired: true); try start(value) } catch { emit("failed"); stop() }
            case "approve": if introduction != nil && listener == nil { startListener() }
            case "reset": if peer != nil { reset() }
            case "stop": stop()
            default: stop()
            }
        }
    }
    func start(_ value: PairingInvitation) throws {
        invitation = value
        let manager = ConnectionManager(serviceID: try NearbyBleProtocol.serviceID(value), strategy: .pointToPoint)
        self.manager = manager; manager.delegate = self
        manager.setAwdlEnabledForProbe(false)
        manager.restrictUpgradesForOfflineProbe()
        let advertiser = Advertiser(connectionManager: manager); self.advertiser = advertiser;
        advertiser.delegate = self
        advertiser.startAdvertising(using: try NearbyBleProtocol.context("mac", value), mediums: [.ble]) {
            [weak self] error in
            if error == nil { self?.emit("advertising") } else { self?.emit("advertising_failed"); self?.stop() }
        }
    }
    func advertiser(
        _ advertiser: Advertiser, didReceiveConnectionRequestFrom endpointID: EndpointID, with context: Data,
        connectionRequestHandler: @escaping (Bool) -> Void
    ) {
        attempts = attempts.filter { $0 > Date().timeIntervalSince1970 - 60 }
        guard !stopped, peer == nil, attempts.count < 6, let invitation,
            let expected = try? NearbyBleProtocol.context("phone", invitation), context == expected
        else { connectionRequestHandler(false); return }
        attempts.append(Date().timeIntervalSince1970)
        peer = endpointID; connectionRequestHandler(true)
        let run = generation
        let deadline = DispatchWorkItem { [weak self] in if self?.generation == run { self?.reset() } }
        sessionDeadline = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: deadline)
    }
    func connectionManager(
        _ connectionManager: ConnectionManager, didReceive verificationCode: String, from endpointID: EndpointID,
        verificationHandler: @escaping (Bool) -> Void
    ) {
        // This transport is not the application trust boundary. HMAC discovery
        // filters candidates; the parent verifies the introduction, certificate
        // pin and QR session secret before application messages are accepted.
        verificationHandler(!stopped && peer == endpointID)
    }
    func connectionManager(
        _ connectionManager: ConnectionManager, didChangeTo state: ConnectionState, for endpointID: EndpointID
    ) {
        guard peer == endpointID else { return }
        switch state {
        case .connected: emit("ble_connected")
        case .disconnected, .rejected: reset()
        default: break
        }
    }
    func connectionManager(
        _ connectionManager: ConnectionManager, didReceive data: Data, withID payloadID: PayloadID,
        from endpointID: EndpointID
    ) {
        guard peer == endpointID, !stopped else { return }
        do {
            switch try NearbyBleProtocol.decode(data) {
            case .introduction(let data):
                guard introduction == nil, let invitation else { reset(); return }
                let intro = try PairingIntroductionCodec.decodeIntroduction(data, invitationID: invitation.id)
                guard intro.verify(invitation: invitation) else { reset(); return }
                introduction = intro
                emit("introduction", ["data": data.base64EncodedString()])
            case .bytes(let sequence, let bytes):
                guard introduction != nil, sequence == receiveSequence, !receiving, pendingInbound == nil else {
                    reset(); return
                }
                if local == nil { pendingInbound = .bytes(sequence, bytes) } else { receiveBytes(sequence, bytes) }
            case .acknowledgement(let sequence):
                guard waitingAck == sequence else { reset(); return }
                ackDeadline?.cancel(); ackDeadline = nil; waitingAck = nil
                readLocal()
            }
        } catch { reset() }
    }
    func startListener() {
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let server = try NWListener(using: parameters)
            listener = server
            let run = generation
            server.stateUpdateHandler = { [weak self, weak server] state in
                guard let self, self.generation == run else { return }
                if case .ready = state, let port = server?.port {
                    self.emit("relay_ready", ["port": Int(port.rawValue)])
                }
                if case .failed = state { self.reset() }
            }
            server.newConnectionHandler = { [weak self] connection in
                guard let self, self.generation == run, !self.acceptedLocal else { connection.cancel(); return }
                self.acceptedLocal = true; self.local = connection
                connection.stateUpdateHandler = { [weak self] state in
                    guard let self, self.generation == run else { return }
                    switch state {
                    case .ready:
                        self.sessionDeadline?.cancel(); self.sessionDeadline = nil
                        if case .bytes(let seq, let data) = self.pendingInbound {
                            self.pendingInbound = nil; self.receiveBytes(seq, data)
                        }
                        self.readLocal()
                    case .failed, .cancelled: self.reset()
                    default: break
                    }
                }
                connection.start(queue: .main)
            }
            server.start(queue: .main)
        } catch { reset() }
    }
    func receiveBytes(_ sequence: UInt32, _ bytes: Data) {
        guard let local, !receiving else { reset(); return }
        receiving = true
        let run = generation
        local.send(
            content: bytes,
            completion: .contentProcessed { [weak self] error in
                guard let self, self.generation == run else { return }
                guard error == nil else { self.reset(); return }
                self.receiving = false; self.receiveSequence &+= 1; self.bytesIn += UInt64(bytes.count)
                self.send(.acknowledgement(sequence))
            })
    }
    func readLocal() {
        guard waitingAck == nil, let local, peer != nil else { return }
        let run = generation
        local.receive(minimumIncompleteLength: 1, maximumLength: NearbyBleProtocol.maxChunk) {
            [weak self] data, _, complete, error in
            guard let self, self.generation == run else { return }
            guard error == nil, !complete, let data, !data.isEmpty else { self.reset(); return }
            let sequence = self.transmitSequence; self.transmitSequence &+= 1
            self.waitingAck = sequence; self.bytesOut += UInt64(data.count)
            self.send(.bytes(sequence, data))
            let deadline = DispatchWorkItem { [weak self] in
                if self?.generation == run && self?.waitingAck == sequence { self?.reset() }
            }
            self.ackDeadline = deadline; DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: deadline)
        }
    }
    func send(_ packet: NearbyBleProtocol.Packet) {
        guard let peer, let manager, let data = try? NearbyBleProtocol.encode(packet) else { return }
        let run = generation
        _ = manager.send(data, to: [peer]) { [weak self] error in
            if error != nil && self?.generation == run { self?.reset() }
        }
    }
    func connectionManager(
        _ connectionManager: ConnectionManager, didReceive stream: InputStream, withID payloadID: PayloadID,
        from endpointID: EndpointID, cancellationToken token: CancellationToken
    ) { token.cancel(); reset() }
    func connectionManager(
        _ connectionManager: ConnectionManager, didStartReceivingResourceWithID payloadID: PayloadID,
        from endpointID: EndpointID, at localURL: URL, withName name: String, cancellationToken token: CancellationToken
    ) { token.cancel(); reset() }
    func connectionManager(
        _ connectionManager: ConnectionManager, didReceiveTransferUpdate update: TransferUpdate,
        from endpointID: EndpointID, forPayload payloadID: PayloadID
    ) {
        if case .failure = update, peer == endpointID { reset() }
    }
    func reset() {
        guard peer != nil || listener != nil else { return }
        generation = UUID()
        let previous = peer; peer = nil
        local?.stateUpdateHandler = nil; local?.cancel(); local = nil
        listener?.stateUpdateHandler = nil; listener?.cancel(); listener = nil
        ackDeadline?.cancel(); ackDeadline = nil; sessionDeadline?.cancel(); sessionDeadline = nil
        introduction = nil; pendingInbound = nil; waitingAck = nil; receiving = false; acceptedLocal = false
        transmitSequence = 0; receiveSequence = 0
        if let previous { manager?.disconnect(from: previous) }
        emit("closed", ["bytesIn": bytesIn, "bytesOut": bytesOut])
    }
    func stop() {
        guard !stopped else { return }; stopped = true
        reset(); advertiser?.stopAdvertising()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
    }
}

let application = NSApplication.shared
Darwin.signal(SIGPIPE, SIG_IGN)
application.setActivationPolicy(.accessory)
let bridge = BleBridge()
FileHandle.standardInput.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { handle.readabilityHandler = nil }
    DispatchQueue.main.async { bridge.input(data) }
}
application.run()
