import Foundation
import XCTest
@testable import Androfest

final class HelperEventStreamTests: XCTestCase {
    func testFragmentedAndCoalescedEvents() throws {
        var stream = HelperEventStream()
        XCTAssertTrue(try stream.append(Data("{\"event\":\"adver".utf8)).isEmpty)
        let records = try stream.append(Data("tising\"}\n{\"event\":\"closed\"}\n".utf8))
        XCTAssertEqual(records.compactMap { $0["event"] as? String }, ["advertising", "closed"])
    }

    func testMalformedRecordsDoNotHideFollowingValidEvent() throws {
        var stream = HelperEventStream()
        let records = try stream.append(Data("garbage\n[]\n{\"event\":\"closed\"}\n".utf8))
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0]["event"] as? String, "closed")
    }

    func testUnterminatedOversizedRecordFailsBeforeAppend() throws {
        var stream = HelperEventStream()
        _ = try stream.append(Data(repeating: 65, count: HelperEventStream.maxBufferedBytes))
        XCTAssertThrowsError(try stream.append(Data([65])))
    }
}
