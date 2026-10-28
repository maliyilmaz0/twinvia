import AppKit
import Combine
import Foundation
import TwinviaProtocol

@MainActor
final class RemoteControlModel: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var imageWidth = 0
    @Published private(set) var imageHeight = 0
    @Published private(set) var message = "Start a five-minute screen-control session on your phone, then refresh here."
    @Published private(set) var busy = false
    private var pending: (id: String, action: DeviceAction, started: Date, timeout: Task<Void, Never>)?
    private let send: (DeviceCommand) throws -> String

    init(send: @escaping (DeviceCommand) throws -> String) { self.send = send }

    func connected() {
        message = "Connected. Start screen viewing on your phone, then refresh here."
    }

    func request(_ action: DeviceAction, key: String? = nil) {
        guard pending == nil else { return }
        do {
            let id = try send(DeviceCommand(action: action, key: key))
            busy = true
            message = action == .remoteSnapshot ? "Loading phone screen over Bluetooth…" : "Sending action to phone…"
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
        if let screen = result.screen, let bytes = Data(base64Encoded: screen.jpegBase64),
            let next = NSImage(data: bytes)
        {
            image = next
            imageWidth = screen.width; imageHeight = screen.height
        }
        if result.success, pending.action == .remoteSnapshot, let screen = result.screen,
            let bytes = Data(base64Encoded: screen.jpegBase64)
        {
            message = String(
                format: "Phone screen updated · %.1f KiB · %.1f s over Bluetooth",
                Double(bytes.count) / 1024, Date().timeIntervalSince(pending.started)
            )
        } else {
            message = result.message
        }
        if result.success && pending.action != .remoteSnapshot {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.request(.remoteSnapshot)
            }
        }
    }

    func disconnected() {
        pending?.timeout.cancel(); pending = nil; busy = false
        image = nil; imageWidth = 0; imageHeight = 0
        message = "Phone disconnected. Start a new screen-control session after reconnecting."
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
