import Foundation

/// Bound bytes AND callback count before posting Bluetooth data to the main actor.
final class RemoteIngressBudget: @unchecked Sendable {
    struct Ticket: Sendable { let generation: UInt64; let bytes: Int }
    enum Admission { case chunk(Ticket), overflow(UInt64), ignored }
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var bytes = 0
    private var callbacks = 0
    private var closed = false
    private let limit: Int
    init(limit: Int = 262_172) { self.limit = limit }
    func reserve(_ count: Int) -> Admission {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return .ignored }
        guard count > 0, count <= limit - bytes, callbacks < 128 else {
            closed = true; return .overflow(generation)
        }
        bytes += count; callbacks += 1
        return .chunk(Ticket(generation: generation, bytes: count))
    }
    func release(_ ticket: Ticket) {
        lock.lock(); defer { lock.unlock() }
        guard ticket.generation == generation else { return }
        bytes -= ticket.bytes; callbacks -= 1
    }
    func matches(_ value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == value
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; bytes = 0; callbacks = 0; closed = false
    }
}
