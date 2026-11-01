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
    func testLocalScreenEndpointsRejectPublicNamesAndUnboundedPorts() throws {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        for host in ["10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.76"] {
            try RemoteChannel(session: UUID().uuidString, key: key, host: host, port: 54321).validate()
        }
        for host in [
            "example.com", "127.0.0.1", "8.8.8.8", "172.32.0.1", "192.168.001.2", "192.168.1.999", "192.168.1.2%en0",
        ] {
            XCTAssertThrowsError(
                try RemoteChannel(session: UUID().uuidString, key: key, host: host, port: 54321).validate())
        }
        XCTAssertThrowsError(
            try RemoteChannel(session: UUID().uuidString, key: key, host: "192.168.1.2", port: 80).validate())
        XCTAssertThrowsError(try RemoteChannel(session: UUID().uuidString, key: key, host: "192.168.1.2").validate())
    }

}
