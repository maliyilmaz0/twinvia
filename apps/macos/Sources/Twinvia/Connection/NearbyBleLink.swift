import TwinviaProtocol
import AppKit
import Darwin
import Foundation

/// Owns an ordinary-permission SDK process. The UI process keeps TLS and trust.
@MainActor
final class NearbyBleLink: PeerLink {
    var onStatus: ((String) -> Void)?
    var onIntroduction: ((PairingIntroduction) -> Bool)?
    var onReady: ((UInt16, PairingIntroduction) -> Void)?
    var onClosed: (() -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var events = HelperEventStream()
    private var invitation: PairingInvitation?
    private var introduction: PairingIntroduction?
    private var generation = UUID()
    private var stopped = false
    private var suspended = false
    private var retry: Task<Void, Never>?
    private var retrySeconds = 2
    private var observers: [NSObjectProtocol] = []
    private(set) var diagnosticState = "starting"
    var isRunning: Bool { !stopped }
    static var executable: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("TwinviaBluetooth.app/Contents/MacOS/TwinviaBleBridge")
    }
    static var available: Bool { executable.map { FileManager.default.isExecutableFile(atPath: $0.path) } == true }

    func start(invitation: PairingInvitation) {
        guard self.invitation == nil, !stopped else { return }
        self.invitation = invitation
        // A child disappearing between isRunning and write must produce EPIPE,
        // not terminate the menu-bar application with SIGPIPE.
        Darwin.signal(SIGPIPE, SIG_IGN)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }; self.suspended = true
                    self.retry?.cancel(); self.retry = nil; self.terminateChild(); self.onClosed?()
                }
            })
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.suspended = false; self?.scheduleRestart()
                }
            })
        launch()
    }
    private func launch() {
        guard !stopped, !suspended, let invitation, let executable = Self.executable else { return }
        generation = UUID(); let run = generation
        let child = Process(), commands = Pipe(), events = Pipe()
        child.executableURL = executable
        child.standardInput = commands; child.standardOutput = events; child.standardError = FileHandle.nullDevice
        input = commands; output = events; process = child; self.events = HelperEventStream(); introduction = nil
        events.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            Task { @MainActor in
                guard let self, self.generation == run, !self.stopped else { return }
                self.consume(data)
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == run, !self.stopped else { return }
                self.scheduleRestart()
            }
        }
        do {
            try child.run()
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(invitation))
            command(["command": "configure", "invitation": object])
            diagnosticState = "ble_starting"; onStatus?("Preparing Bluetooth connection")
        } catch { scheduleRestart() }
    }
    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        guard let records = try? events.append(data) else { scheduleRestart(); return }
        for record in records {
            guard let event = record["event"] as? String else { continue }
            diagnosticState = event
            switch event {
            case "advertising": onStatus?("Waiting for your phone over Bluetooth")
            case "ble_connected": onStatus?("Verifying phone identity")
            case "introduction":
                guard let invitation, let encoded = record["data"] as? String, let data = Data(base64Encoded: encoded),
                    let intro = try? PairingIntroductionCodec.decodeIntroduction(data, invitationID: invitation.id),
                    onIntroduction?(intro) == true
                else { command(["command": "reset"]); continue }
                introduction = intro; command(["command": "approve"])
            case "relay_ready":
                guard let intro = introduction, let number = record["port"] as? Int, let port = UInt16(exactly: number),
                    port > 0
                else { continue }
                retrySeconds = 2; onReady?(port, intro)
            case "closed": introduction = nil; onClosed?()
            case "advertising_failed": onStatus?("Could not advertise · Check Bluetooth permission and radio")
            default: break
            }
        }
    }
    private func command(_ object: [String: Any]) {
        guard process?.isRunning == true, let input, let bytes = try? JSONSerialization.data(withJSONObject: object)
        else { return }
        try? input.fileHandleForWriting.write(contentsOf: bytes + Data([10]))
    }
    private func scheduleRestart() {
        guard !stopped, !suspended, retry == nil else { return }
        terminateChild(); diagnosticState = "ble_retrying"; onClosed?()
        onStatus?("Retrying Bluetooth connection")
        let seconds = retrySeconds; retrySeconds = min(30, seconds * 2)
        retry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.retry = nil; self?.launch()
        }
    }
    private func terminateChild(graceful: Bool = false) {
        generation = UUID()
        output?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        if graceful, let process {
            let deadline = Date().addingTimeInterval(1.5)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        }
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; introduction = nil
    }
    func retryEndpoint() { command(["command": "reset"]) }
    func setRealtimeAudio(_ enabled: Bool) {}
    func stop() {
        guard !stopped else { return }; stopped = true
        retry?.cancel(); retry = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll(); command(["command": "stop"]); terminateChild(graceful: true)
    }
}
