import XCTest
@testable import Twinvia

final class RemoteIngressBudgetTests: XCTestCase {
    func testByteAndCallbackLimitsDoNotQueueUnboundedWork() {
        let budget = RemoteIngressBudget(limit: 256)
        var tickets: [RemoteIngressBudget.Ticket] = []
        for _ in 0..<128 {
            if case .chunk(let ticket) = budget.reserve(1) {
                tickets.append(ticket)
            } else {
                XCTFail("Unexpected rejection")
            }
        }
        XCTAssertEqual(tickets.count, 128)
        if case .overflow = budget.reserve(1) {} else { XCTFail("Callback budget must reject") }
        if case .ignored = budget.reserve(1) {} else { XCTFail("Overflow must only schedule one failure") }
        budget.reset()
        for ticket in tickets { budget.release(ticket) }
        if case .chunk = budget.reserve(256) {} else { XCTFail("Stale releases must not corrupt the new budget") }
        if case .overflow = budget.reserve(1) {} else { XCTFail("Byte budget must reject") }
    }
}
