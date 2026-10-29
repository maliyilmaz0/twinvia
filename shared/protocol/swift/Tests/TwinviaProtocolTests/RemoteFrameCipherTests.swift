import Foundation
import XCTest
@testable import TwinviaProtocol

final class RemoteFrameCipherTests: XCTestCase {
    func testIndependentVectorAndAuthenticationFailures() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("fixtures/remote-fast-vector.json"))
        let vector = try JSONDecoder().decode([String: String].self, from: data)
        let channel = RemoteChannel(session: vector["session"]!, key: vector["key"]!)
        var mac = try RemoteFrameCipher(channel: channel, mac: true)
        var phone = try RemoteFrameCipher(channel: channel, mac: false)
        let frame = try mac.seal(Data(vector["plain"]!.utf8))
        XCTAssertEqual(frame.map { String(format: "%02x", $0) }.joined(), vector["sealed"]!)
        XCTAssertThrowsError(try mac.open(frame))
        var corrupt = frame; corrupt[corrupt.count - 1] ^= 1
        XCTAssertThrowsError(try phone.open(corrupt))
        let next = try mac.seal(Data("next".utf8))
        XCTAssertThrowsError(try phone.open(next))
        XCTAssertEqual(try phone.open(frame), Data(vector["plain"]!.utf8))
        XCTAssertThrowsError(try phone.open(frame))
        XCTAssertEqual(try phone.open(next), Data("next".utf8))
        XCTAssertEqual(try mac.open(phone.seal(Data("response".utf8))), Data("response".utf8))
        XCTAssertThrowsError(try mac.seal(Data(repeating: 0, count: WireCodec.maxMessageBytes + 1)))
    }
}
