import XCTest
@testable import Twinvia

final class RemoteScrollInputTests: XCTestCase {
    func testCoalescesAndThrottlesWheelBurstsWithoutReplayingMomentum() {
        var input = RemoteScrollInput()
        XCTAssertNil(input.consume(delta: 12, timestamp: 1))
        XCTAssertEqual(input.consume(delta: 12, timestamp: 1.01), .up)
        XCTAssertNil(input.consume(delta: 100, timestamp: 1.1))
        XCTAssertNil(input.consume(delta: 1, timestamp: 1.5))
        XCTAssertEqual(input.consume(delta: -30, timestamp: 1.6), .down)
        XCTAssertNil(input.consume(delta: .infinity, timestamp: 2))
        XCTAssertNil(input.consume(delta: .nan, timestamp: 2))
    }
}
