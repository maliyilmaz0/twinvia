import AppKit
import Combine
import Foundation
import TwinviaProtocol

@MainActor
final class RemoteControlModel: ObservableObject {
    struct FrameMetrics: Codable {
        let width: Int; let height: Int; let bytes: Int; let seconds: Double; let transport: String
    }
    private(set) var frameMetrics: FrameMetrics?
    private(set) var frameSequence = 0
    enum Quality: String, CaseIterable { case responsive = "Responsive", detail = "Detail" }
    @Published private(set) var viewingAllowed: Bool?
    @Published private(set) var controlAllowed: Bool?
    private var imageExpiry: Task<Void, Never>?
    @Published var quality = Quality.responsive
    @Published private(set) var preview = false
    @Published private(set) var fastConnected = false
    @Published private(set) var loadingFrame = false
    private let fast = RemoteFastLink()
    private let lan = RemoteLANLink()
    private var useLAN = false
    private var screenLink: any RemoteScreenLink { useLAN ? lan : fast }
    @Published private(set) var screenTransport = "Bluetooth LE"
    private(set) var lanAvailable = false
    func connectLAN() {
        guard lanAvailable else { message = "Update the phone app to enable the Wi-Fi screen lane."; return }
        guard !busy, !loadingFrame else { return }
        fast.close(); lan.close(); fastConnected = false; useLAN = true
        setPreview(false); request(.remoteLANOpen)
    }
    func useBLE() {
        fast.close(); lan.close(); useLAN = false; fastConnected = false; loadingFrame = false
        setPreview(false); image = nil; frameMetrics = nil; screenTransport = "Bluetooth LE"
        message = "Bluetooth LE selected. Refresh a new frame when ready."
    }
    private var fastAddress: String?
    func connectFast(address: String) {
        guard !busy, !loadingFrame else { return }
        lan.close(); fast.close(); fastConnected = false; useLAN = false
        setPreview(false)
        fastAddress = address
        request(.remoteFastOpen)
    }
    private var supportsDetail = false
    private var refreshTask: Task<Void, Never>?
    func configure(supportsDetail: Bool, supportsLAN: Bool = false) {
        self.supportsDetail = supportsDetail; lanAvailable = supportsLAN
    }
    func requestFrame() {
        guard !loadingFrame else { return }
        if screenLink.ready {
            let started = Date()
            loadingFrame = true
            screenLink.request(detail: quality == .detail) { [weak self] result in
                guard let self else { return }
                self.loadingFrame = false
                switch result {
                case .success(let screen):
                    self.fastConnected = true
                    self.display(screen, started: started, transport: self.useLAN ? "Wi-Fi LAN" : "Bluetooth Classic")
                    if self.preview { self.scheduleFrame() }
                case .failure(let error):
                    self.message = error.localizedDescription
                    self.fastConnected = false; self.setPreview(false); self.image = nil
                }
            }
        } else {
            request(quality == .detail && supportsDetail ? .remoteSnapshotDetail : .remoteSnapshot)
        }
    }
    private func scheduleFrame() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.requestFrame()
        }
    }
    private func display(_ screen: RemoteScreen, started: Date, transport: String) {
        guard let bytes = Data(base64Encoded: screen.jpegBase64), let next = ScreenImageDecoder.decode(screen) else {
            setPreview(false); image = nil; message = "The phone returned an invalid screen image."
            return
        }
        screenTransport = transport
        image = next; imageWidth = screen.width; imageHeight = screen.height
        imageExpiry?.cancel()
        imageExpiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            self?.disconnected(); self?.message = "Preview expired. Request a fresh frame."
        }
        frameSequence += 1
        frameMetrics = FrameMetrics(
            width: screen.width, height: screen.height, bytes: bytes.count,
            seconds: Date().timeIntervalSince(started), transport: transport)
        message = String(
            format: "%.0f × %.0f · %.1f KiB · %.1f s · %@", Double(screen.width), Double(screen.height),
            Double(bytes.count) / 1024, Date().timeIntervalSince(started), transport)
    }
    func setPreview(_ enabled: Bool) {
        preview = enabled
        refreshTask?.cancel(); refreshTask = nil
        if enabled { requestFrame() }
    }
    func type(_ text: String) { request(.remoteText, text: text) }
    func key(_ value: String) { request(.remoteKey, key: value) }
    private func isFrame(_ action: DeviceAction) -> Bool {
        action == .remoteSnapshot || action == .remoteSnapshotDetail
    }
    @Published private(set) var image: NSImage?
    @Published private(set) var imageWidth = 0
    @Published private(set) var imageHeight = 0
    @Published private(set) var message = "Start a five-minute screen-control session on your phone, then refresh here."
    @Published private(set) var busy = false
    private var pending: (id: String, action: DeviceAction, started: Date, timeout: Task<Void, Never>)?
    private let send: (DeviceCommand) throws -> String

    init(send: @escaping (DeviceCommand) throws -> String) {
        self.send = send
        for link in [fast as any RemoteScreenLink, lan as any RemoteScreenLink] {
            link.onReady = { [weak self] in
                self?.quality = .detail; self?.setPreview(true)
            }
            link.onFailure = { [weak self] message in
                self?.fastConnected = false; self?.loadingFrame = false
                self?.setPreview(false); self?.message = message; self?.image = nil
            }
        }
    }

    func updateSession(_ status: DeviceStatus) {
        viewingAllowed = status.locked ? false : status.remoteViewing
        controlAllowed = status.locked ? false : status.remoteControl
        if status.locked || status.remoteViewing == false {
            disconnected()
            viewingAllowed = false; controlAllowed = false
            message =
                status.locked
                ? "Phone locked. Unlock and approve a new screen session." : "Approve screen viewing on your phone."
        }
    }

    func connected() {
        viewingAllowed = nil; controlAllowed = nil
        message = "Connected. Start screen viewing on your phone, then refresh here."
    }

    func request(_ action: DeviceAction, key: String? = nil, text: String? = nil) {
        guard pending == nil else { return }
        if [.remoteTap, .remoteSwipe, .remoteText, .remoteKey, .remoteBack, .remoteHome, .remoteNotifications].contains(
            action), controlAllowed == false
        {
            message = "Approve touch control on your phone first."; return
        }
        do {
            let id = try send(DeviceCommand(action: action, text: text, key: key))
            busy = true
            message = isFrame(action) ? "Loading phone screen over Bluetooth…" : "Sending action to phone…"
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                guard let self, self.pending?.id == id else { return }
                self.disconnected()
                self.message = "The phone did not respond. Check the screen-control session and connection."
            }
            pending = (id, action, Date(), timeout)
        } catch { message = error.localizedDescription }
    }

    func tap(x: Double, y: Double) {
        let x = Int((x * 10_000).rounded()).clamped(to: 0...10_000)
        let y = Int((y * 10_000).rounded()).clamped(to: 0...10_000)
        request(.remoteTap, key: "\(x),\(y)")
    }

    func scroll(_ direction: RemoteScrollDirection) {
        let from = direction == .up ? 0.35 : 0.75
        let to = direction == .up ? 0.75 : 0.35
        swipe(from: CGPoint(x: 0.5, y: from), to: CGPoint(x: 0.5, y: to))
    }

    func swipe(from start: CGPoint, to end: CGPoint, durationMs: Int = 300) {
        func coordinate(_ value: Double) -> Int {
            Int((value * 10_000).rounded()).clamped(to: 0...10_000)
        }
        request(
            .remoteSwipe,
            key: "\(coordinate(start.x)),\(coordinate(start.y)),\(coordinate(end.x)),\(coordinate(end.y)),\(durationMs)"
        )
    }

    func receive(_ result: CommandResult) {
        guard let pending, pending.id == result.requestId else { return }
        pending.timeout.cancel(); self.pending = nil; busy = false
        if result.success, let channel = result.channel, pending.action == .remoteLANOpen {
            do { try lan.connect(credentials: channel); message = "Connecting the encrypted Wi-Fi screen lane…" } catch
            { message = error.localizedDescription }
            return
        }
        if result.success, let channel = result.channel, pending.action == .remoteFastOpen, let address = fastAddress {
            do {
                try fast.connect(address: address, credentials: channel)
                message = "Connecting the optional Bluetooth Classic screen lane…"
            } catch { message = error.localizedDescription }
            return
        }
        if result.success, isFrame(pending.action), let screen = result.screen {
            display(screen, started: pending.started, transport: "Bluetooth LE")
        } else {
            message = result.message
        }
        if !result.success {
            setPreview(false)
            image = nil; frameMetrics = nil; fast.close(); lan.close(); fastConnected = false; loadingFrame = false
        }
        if result.success && pending.action != .remoteFastOpen && pending.action != .remoteLANOpen
            && (!isFrame(pending.action) || preview)
        {
            scheduleFrame()
        }
    }

    func closeMirror() {
        disconnected()
        message = "Mirror closed. Reopen it and confirm the phone session before refreshing."
    }

    func prepareForSleep() {
        disconnected()
        message = "Preview paused for sleep. Confirm the phone session after waking, then refresh."
    }

    func disconnected() {
        imageExpiry?.cancel(); imageExpiry = nil
        fast.close(); lan.close(); screenTransport = "Bluetooth LE"; fastConnected = false; loadingFrame = false
        setPreview(false)
        pending?.timeout.cancel(); pending = nil; busy = false
        image = nil; imageWidth = 0; imageHeight = 0; frameMetrics = nil
        message = "Phone disconnected. Start a new screen-control session after reconnecting."
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
