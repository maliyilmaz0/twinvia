import Combine
import Foundation

/// A local, timed pause. Only its deadline is persisted; no paused content is queued.
@MainActor
final class PrivacyBreak: ObservableObject {
    enum Duration: Int, CaseIterable { case five = 5, fifteen = 15, sixty = 60 }
    @Published private(set) var until: Date?
    var active: Bool { until != nil }
    var onChange: ((Bool) -> Void)?
    private let now: () -> Date
    private let save: (Date?) -> Void
    private let scheduleExpiry: Bool
    private var expiry: Task<Void, Never>?

    init(
        savedUntil: Date? = nil, now: @escaping () -> Date = Date.init,
        scheduleExpiry: Bool = true, save: @escaping (Date?) -> Void = { _ in }
    ) {
        self.now = now; self.save = save; self.scheduleExpiry = scheduleExpiry
        if let savedUntil, savedUntil > now(), savedUntil.timeIntervalSince(now()) <= 3600 {
            until = savedUntil
            armExpiry()
        } else {
            until = nil; save(nil)
        }
    }

    func start(_ duration: Duration) {
        until = now().addingTimeInterval(Double(duration.rawValue * 60))
        save(until); armExpiry(); onChange?(true)
    }

    func resume() {
        guard active else { return }
        expiry?.cancel(); expiry = nil; until = nil
        save(nil); onChange?(false)
    }

    func refresh() {
        if let until, until <= now() { resume() }
    }

    private func armExpiry() {
        expiry?.cancel()
        guard scheduleExpiry, let until else { return }
        let seconds = max(0, until.timeIntervalSince(now()))
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.resume()
        }
    }
}
