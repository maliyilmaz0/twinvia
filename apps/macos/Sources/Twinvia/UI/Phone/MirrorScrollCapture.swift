import AppKit
import SwiftUI

/// Watches only wheel events over the fitted phone image; clicks still reach SwiftUI.
struct MirrorScrollCapture: NSViewRepresentable {
    let enabled: Bool
    let onScroll: (RemoteScrollDirection) -> Void
    func makeNSView(context: Context) -> PhoneWheelView { PhoneWheelView() }
    func updateNSView(_ view: PhoneWheelView, context: Context) {
        view.enabled = enabled; view.onScroll = onScroll
        if !enabled { view.input = RemoteScrollInput() }
    }
    static func dismantleNSView(_ view: PhoneWheelView, coordinator: ()) { view.stop() }
}

@MainActor
final class PhoneWheelView: NSView {
    var enabled = false
    var onScroll: ((RemoteScrollDirection) -> Void)?
    var input = RemoteScrollInput()
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.enabled, let window = self.window, window.isVisible,
                event.window == window, self.visibleRect.contains(self.convert(event.locationInWindow, from: nil))
            else { return event }
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 24)
            if let direction = self.input.consume(delta: delta, timestamp: event.timestamp) {
                self.onScroll?(direction)
            }
            return nil
        }
    }
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; input = RemoteScrollInput()
    }
}
