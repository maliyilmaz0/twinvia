import XCTest
@testable import Androfest

final class MessageReplayWindowTests: XCTestCase {
    func testDuplicateDoesNotConsumeCapacityOrRefreshItsPosition() {
        var history = MessageReplayWindow(capacity: 2)
        XCTAssertTrue(history.insert("a"))
        XCTAssertTrue(history.insert("b"))
        XCTAssertFalse(history.insert("a"))
        XCTAssertTrue(history.insert("c"))
        XCTAssertFalse(history.insert("b"))
        XCTAssertTrue(history.insert("a"))
    }
}
