/// Bounded session-independent receipt history. The owner serializes access on MainActor.
struct MessageReplayWindow {
    private let capacity: Int
    private var order: [String] = []
    private var identifiers: Set<String> = []

    init(capacity: Int = 128) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    mutating func insert(_ identifier: String) -> Bool {
        guard identifiers.insert(identifier).inserted else { return false }
        order.append(identifier)
        if order.count > capacity { identifiers.remove(order.removeFirst()) }
        return true
    }
}
