import Combine
import CoreAudio
import Foundation
@preconcurrency import IOBluetooth

/// Experimental HFP client. It never dials, answers or changes audio routes automatically.
/// It owns only its HFP service, independently of the notification RFCOMM connection.
@MainActor
final class HandsFreeController: NSObject, ObservableObject, IOBluetoothHandsFreeDeviceDelegate {
    @Published private(set) var status = "Waiting for call service"
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var callActive = false
    @Published private(set) var callSetup = 0
    @Published private(set) var callHeld = 0
    @Published private(set) var scoConnected = false
    @Published private(set) var phoneName = "Phone"
    @Published private(set) var audioStatus = "Waiting for audio relay"
    @Published private(set) var audioUnsupported = false
    @Published private(set) var audioDevices: [CallAudioDevice] = []
    @Published private(set) var events: [String] = []
    private(set) var incomingID: UUID?
    var onIncoming: ((UUID) -> Void)?
    var onIncomingEnded: (() -> Void)?
    private var handsFree: IOBluetoothHandsFreeDevice?
    private var deadline: Task<Void, Never>?
    private var poll: Task<Void, Never>?
    private var audioDeadline: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var desiredAddress: String?
    private var wantsConnection = false
    private var sleeping = false
    private let reportURL: URL?
    private var eventRecords: [[String: String]] = []

    init(reportURL: URL? = nil) {
        self.reportURL = reportURL
        super.init()
    }

    var canAnswer: Bool { connected && callSetup == 1 && !callActive && callHeld == 0 }
    var canEnd: Bool { connected && (callActive || callSetup != 0 || callHeld != 0) }
    var callDescription: String {
        if !connected { return "Call status unknown" }
        if callHeld != 0 { return "A call is on hold" }
        if callActive { return "Call in progress" }
        switch callSetup {
        case 1: return "Incoming call"
        case 2: return "Dialing number"
        case 3: return "The other phone is ringing"
        default: return "No active call"
        }
    }

    func connect(address: String?) {
        guard let address, let device = IOBluetoothDevice(addressString: address), device.isPaired() else {
            status = "Select the paired Bluetooth phone in Twinvia first."
            record("unpaired")
            return
        }
        desiredAddress = address
        wantsConnection = true
        guard !sleeping, !connected, !connecting else { return }
        reconnect?.cancel(); reconnect = nil
        releaseSession(disconnect: true)
        phoneName = device.name ?? "Phone"
        guard let client = IOBluetoothHandsFreeDevice(device: device, delegate: self) else {
            status = "Could not create the macOS HFP client."
            record("init-failed")
            return
        }
        // Caller ID and enhanced call status only. Do not advertise codecs or DSP we do not implement.
        client.supportedFeatures = (1 << 2) | (1 << 5)
        handsFree = client
        audioUnsupported = false
        connecting = true
        status = "Connecting Bluetooth call service"
        record("connect-requested")
        refreshAudioDevices()
        client.connect()
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !self.connected else { return }
            self.status = "HFP did not respond; check Bluetooth call permission on your phone."
            self.record("connect-timeout")
            self.releaseSession(disconnect: true)
            self.scheduleReconnect(after: .seconds(5))
        }
        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self else { return }
                // Read actual state even if an OS version omits a delegate callback.
                if self.handsFree?.isConnected == true { self.updateIndicators() }
                self.refreshAudioDevices()
                self.writeReport()
            }
        }
    }

    func answer() {
        guard canAnswer else { return }
        record("answer-requested")
        handsFree?.acceptCall()
    }

    func answerOnPhone() {
        guard canAnswer else { return }
        record("answer-on-phone-requested")
        handsFree?.acceptCallOnPhone()
    }

    func dial(_ raw: String) {
        guard connected, !callActive, callSetup == 0, callHeld == 0, let number = CallNumber.normalize(raw) else {
            return
        }
        record("dial-requested")
        handsFree?.dialNumber(number)
    }

    func endCall() {
        guard canEnd else { return }
        record("end-requested")
        handsFree?.endCall()
    }

    func audioToComputer() {
        guard connected, !audioUnsupported else { return }
        record("audio-to-mac-requested")
        audioStatus = "Requesting Mac audio handoff"
        handsFree?.transferAudioToComputer()
        watchAudioResult()
    }

    func connectAudioChannel() {
        guard connected, !scoConnected, !audioUnsupported else { return }
        audioStatus = "Opening Bluetooth audio channel"
        record("connect-sco-requested")
        handsFree?.connectSCO()
        watchAudioResult()
    }

    func audioToPhone() {
        guard connected else { return }
        audioDeadline?.cancel()
        audioStatus = "Returning audio to phone"
        record("audio-to-phone-requested")
        handsFree?.transferAudioToPhone()
    }

    private func watchAudioResult() {
        audioDeadline?.cancel()
        audioDeadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            guard let self else { return }
            self.updateIndicators()
            self.refreshAudioDevices()
            if !self.scoConnected {
                self.audioStatus = "macOS could not open Bluetooth audio. Continue using phone audio."
                self.record("audio-channel-timeout")
            } else {
                self.audioStatus = "Audio channel open; Mac microphone and speaker still need verification."
                self.record("audio-channel-open")
            }
        }
    }

    func stop() {
        wantsConnection = false
        desiredAddress = nil
        reconnect?.cancel(); reconnect = nil
        releaseSession(disconnect: true)
    }

    /// IOBluetoothHandsFree can deliver stale RFCOMM data while the machine is
    /// resuming. Detach before sleep so its parser never sees a half-resumed
    /// stream, then create a fresh HFP session after Bluetooth wakes.
    func prepareForSleep() {
        guard !sleeping else { return }
        sleeping = true
        reconnect?.cancel(); reconnect = nil
        if handsFree != nil || connected || connecting { record("system-sleep") }
        releaseSession(disconnect: true)
        if wantsConnection { status = "Mac sleeping · Call service will reconnect after wake" }
    }

    func resumeAfterWake() {
        guard sleeping else { return }
        sleeping = false
        guard wantsConnection else { return }
        status = "Mac woke · Reconnecting Bluetooth call service"
        record("system-wake")
        scheduleReconnect(after: .seconds(3))
    }

    private func scheduleReconnect(after delay: Duration) {
        guard wantsConnection, !sleeping, reconnect == nil, let address = desiredAddress else { return }
        reconnect = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.wantsConnection, !self.sleeping else { return }
            self.reconnect = nil
            self.connect(address: address)
        }
    }

    private func releaseSession(disconnect: Bool) {
        deadline?.cancel()
        poll?.cancel()
        audioDeadline?.cancel()
        deadline = nil; poll = nil; audioDeadline = nil
        // Does not close the device/baseband or the separate Twinvia RFCOMM channel.
        let old = handsFree
        old?.delegate = nil
        handsFree = nil
        if disconnect { old?.disconnect() }
        connected = false
        connecting = false
        callActive = false
        callSetup = 0
        callHeld = 0
        scoConnected = false
        incomingID = nil
        onIncomingEnded?()
    }

    private func updateIndicators() {
        guard let client = handsFree else { return }
        connected = client.isConnected
        callActive = client.indicator(IOBluetoothHandsFreeIndicatorCall) == 1
        callSetup = Int(client.indicator(IOBluetoothHandsFreeIndicatorCallSetup))
        callHeld = Int(client.indicator(IOBluetoothHandsFreeIndicatorCallHeld))
        scoConnected = client.isSCOConnected()
        if connected && callSetup == 1 && !callActive && callHeld == 0 {
            if incomingID == nil { let id = UUID(); incomingID = id; onIncoming?(id) }
        } else if incomingID != nil {
            incomingID = nil; onIncomingEnded?()
        }
    }

    private func record(_ event: String, code: Int? = nil) {
        let detail = code.map { "\(event) (\($0))" } ?? event
        events.insert(detail, at: 0)
        events = Array(events.prefix(30))
        var item = ["time": ISO8601DateFormatter().string(from: Date()), "event": event]
        if let code { item["code"] = String(code) }
        eventRecords.append(item)
        eventRecords = Array(eventRecords.suffix(100))
        writeReport()
    }

    private func writeReport() {
        guard let reportURL else { return }
        let report: [String: Any] = [
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "status": status, "connected": connected, "callActive": callActive,
            "callSetup": callSetup, "callHeld": callHeld, "scoConnected": scoConnected, "audioStatus": audioStatus,
            "audioDevices": audioDevices.map {
                [
                    "name": $0.name, "inputChannels": $0.inputChannels,
                    "outputChannels": $0.outputChannels,
                ] as [String: Any]
            },
            "events": eventRecords,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: reportURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: reportURL.path)
        }
    }

    func refreshAudioDevices() {
        audioDevices = CallAudioDevice.bluetoothDevices()
    }

    private func owns(_ id: ObjectIdentifier) -> Bool {
        handsFree.map { ObjectIdentifier($0) == id } ?? false
    }

    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, connected status: NSNumber!) {
        let id = ObjectIdentifier(device), code = status.intValue
        Task { @MainActor [weak self] in
            guard let self, self.owns(id) else { return }
            self.deadline?.cancel()
            self.connecting = false
            self.updateIndicators()
            self.status =
                self.connected && code == 0 ? "Bluetooth call service connected" : "HFP connection failed: \(code)"
            self.record("connected-callback", code: code)
            if !self.connected {
                self.releaseSession(disconnect: false)
                self.scheduleReconnect(after: .seconds(5))
            }
        }
    }

    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, disconnected status: NSNumber!) {
        let id = ObjectIdentifier(device), code = status.intValue
        Task { @MainActor [weak self] in
            guard let self, self.owns(id) else { return }
            self.releaseSession(disconnect: false)
            self.audioStatus = "Call service disconnected"
            self.status = "Bluetooth call service closed: \(code)"
            self.record("disconnected", code: code)
            self.scheduleReconnect(after: .seconds(5))
        }
    }

    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionOpened status: NSNumber!) {
        let id = ObjectIdentifier(device), code = status.intValue
        Task { @MainActor [weak self] in
            guard let self, self.owns(id) else { return }
            self.audioDeadline?.cancel()
            self.updateIndicators()
            self.refreshAudioDevices()
            if UInt32(truncatingIfNeeded: code) == UInt32(bitPattern: kIOReturnUnsupported) {
                self.audioUnsupported = true
                self.audioStatus = "The macOS audio API is unavailable on this installation (0xE00002C7)."
            } else {
                self.audioStatus =
                    self.scoConnected
                    ? "Bluetooth audio channel open; two-way audio still needs verification."
                    : "Could not open Bluetooth audio channel: \(code)"
            }
            self.record(self.scoConnected && code == 0 ? "sco-opened" : "sco-open-failed", code: code)
        }
    }

    nonisolated func handsFree(_ device: IOBluetoothHandsFree!, scoConnectionClosed status: NSNumber!) {
        let id = ObjectIdentifier(device), code = status.intValue
        Task { @MainActor [weak self] in
            guard let self, self.owns(id) else { return }
            self.scoConnected = false
            self.audioStatus = "Bluetooth audio channel closed"
            self.record("sco-closed", code: code)
        }
    }

    nonisolated func handsFree(_ device: IOBluetoothHandsFreeDevice!, isCallActive value: NSNumber!) {
        indicatorChanged(device, name: "call", value: value.intValue)
    }
    nonisolated func handsFree(_ device: IOBluetoothHandsFreeDevice!, callSetupMode value: NSNumber!) {
        indicatorChanged(device, name: "setup", value: value.intValue)
    }
    nonisolated func handsFree(_ device: IOBluetoothHandsFreeDevice!, callHoldState value: NSNumber!) {
        indicatorChanged(device, name: "held", value: value.intValue)
    }
    nonisolated func handsFree(_ device: IOBluetoothHandsFreeDevice!, ringAttempt value: NSNumber!) {
        indicatorChanged(device, name: "ring", value: value.intValue)
    }
    private nonisolated func indicatorChanged(_ device: IOBluetoothHandsFreeDevice, name: String, value: Int) {
        let id = ObjectIdentifier(device)
        Task { @MainActor [weak self] in
            guard let self, self.owns(id) else { return }
            self.updateIndicators()
            self.record(name, code: value)
        }
    }
}

struct CallAudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let inputChannels: Int
    let outputChannels: Int

    static func bluetoothDevices() -> [CallAudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let read = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        guard read == noErr else { return [] }
        return ids.compactMap { id in
            var transport: UInt32 = 0
            var bytes = UInt32(MemoryLayout<UInt32>.size)
            var key = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(id, &key, 0, nil, &bytes, &transport) == noErr,
                transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
            else { return nil }
            let namePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
            namePointer.initialize(to: nil)
            defer { namePointer.deinitialize(count: 1); namePointer.deallocate() }
            bytes = UInt32(MemoryLayout<CFString?>.size)
            key.mSelector = kAudioObjectPropertyName
            guard AudioObjectGetPropertyData(id, &key, 0, nil, &bytes, namePointer) == noErr,
                let name = namePointer.pointee
            else { return nil }
            return CallAudioDevice(
                id: id, name: name as String,
                inputChannels: channels(id, scope: kAudioDevicePropertyScopeInput),
                outputChannels: channels(id, scope: kAudioDevicePropertyScopeOutput))
        }
    }

    private static func channels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var key = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &key, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &key, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) {
            $0 + Int($1.mNumberChannels)
        }
    }
}
