import AppKit
import Combine
import Foundation
import TwinviaProtocol

@MainActor
final class RemoteControlModel: ObservableObject {
    enum Quality: String, CaseIterable { case responsive = "Responsive", detail = "Detail" }
    @Published var quality = Quality.responsive
    @Published private(set) var preview = false
    @Published private(set) var fastConnected = false
    @Published private(set) var loadingFrame = false
    private let fast = RemoteFastLink()
    private var fastAddress: String?
    func connectFast(address: String) {
        fastAddress = address
        request(.remoteFastOpen)
    }
    private var supportsDetail = false
    private var refreshTask: Task<Void, Never>?
    func configure(supportsDetail: Bool) { self.supportsDetail = supportsDetail }
    func requestFrame() {
        guard !loadingFrame else { return }
        if fast.ready {
            let started = Date()
            loadingFrame = true
            fast.request(detail: quality == .detail) { [weak self] result in
                guard let self else { return }
                self.loadingFrame = false
                switch result {
                case .success(let screen):
                    self.fastConnected = true
                    self.display(screen, started: started, transport: "Bluetooth Classic")
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
        image = next; imageWidth = screen.width; imageHeight = screen.height
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
        fast.onReady = { [weak self] in
            self?.quality = .detail
            self?.setPreview(true)
        }
        fast.onFailure = { [weak self] message in
            self?.fastConnected = false; self?.loadingFrame = false
            self?.setPreview(false); self?.message = message; self?.image = nil
        }
    }

    func connected() {
        message = "Connected. Start screen viewing on your phone, then refresh here."
    }

    func request(_ action: DeviceAction, key: String? = nil, text: String? = nil) {
        guard pending == nil else { return }
        do {
            let id = try send(DeviceCommand(action: action, text: text, key: key))
            busy = true
            message = isFrame(action) ? "Loading phone screen over Bluetooth…" : "Sending action to phone…"
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(45)) } catch { return }
                guard let self, self.pending?.id == id else { return }
                self.pending = nil; self.busy = false
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
            if isFrame(pending.action) { image = nil }
        }
        if result.success && pending.action != .remoteFastOpen && (!isFrame(pending.action) || preview) {
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
        fast.close(); fastConnected = false; loadingFrame = false
        setPreview(false)
        pending?.timeout.cancel(); pending = nil; busy = false
        image = nil; imageWidth = 0; imageHeight = 0
        message = "Phone disconnected. Start a new screen-control session after reconnecting."
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
