import Foundation
import XCTest
@testable import TwinviaProtocol

final class WireFrameTests: XCTestCase {
    func testNetworkOrderAndExactBoundaries() throws {
        XCTAssertEqual(try WireFrame.encode(Data([1, 2, 3])), Data([0, 0, 0, 3, 1, 2, 3]))
        let payload = Data(repeating: 42, count: WireCodec.maxMessageBytes)
        let encoded = try WireFrame.encode(payload)
        XCTAssertEqual(try WireFrame.payloadLength(Data(encoded.prefix(4))), payload.count)
    }

    func testInvalidAndOversizedHeadersAreRejected() {
        for bytes: [UInt8] in [[], [0, 0, 1], [0, 0, 0, 0], [255, 255, 255, 255], [0, 0, 0, 1, 1]] {
            XCTAssertThrowsError(try WireFrame.payloadLength(Data(bytes)))
        }
        XCTAssertThrowsError(try WireFrame.encode(Data()))
        XCTAssertThrowsError(try WireFrame.encode(Data(repeating: 0, count: WireCodec.maxMessageBytes + 1)))
    }
}
