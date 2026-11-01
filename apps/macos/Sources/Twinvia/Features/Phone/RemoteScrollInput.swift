import Foundation

enum RemoteScrollDirection { case up, down }

/// Coalesces a trackpad/wheel burst into bounded, deliberate phone gestures.
struct RemoteScrollInput {
    private var accumulated = 0.0
    private var lastSent = -Double.infinity
    mutating func consume(delta: Double, timestamp: TimeInterval) -> RemoteScrollDirection? {
        guard delta.isFinite, timestamp.isFinite, delta != 0 else { return nil }
        guard timestamp - lastSent >= 0.45 else { accumulated = 0; return nil }
        if accumulated * delta < 0 { accumulated = 0 }
        accumulated = max(-1000, min(1000, accumulated + delta))
        guard abs(accumulated) >= 24 else { return nil }
        let direction: RemoteScrollDirection = accumulated > 0 ? .up : .down
        accumulated = 0; lastSent = timestamp
        return direction
    }
}
