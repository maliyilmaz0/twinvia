import Foundation
import XCTest
@testable import TwinviaProtocol

final class NearbyBleProtocolTests: XCTestCase {
    func testIndependentDiscoveryVectorAndRoleSeparation() throws {
        struct Vector: Decodable { let invitation: PairingInvitation }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/pairing/native-pairing.json")
        let invitation = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url)).invitation
        XCTAssertEqual(try NearbyBleProtocol.serviceID(invitation), "dev.androfest.ble.208ef8258436f653961a5e8c")
        XCTAssertEqual(try NearbyBleProtocol.context("mac", invitation).hex, "4fdf32c91101401eee477ab1cb8795e8")
        XCTAssertEqual(try NearbyBleProtocol.context("phone", invitation).hex, "e8bce6b6ff151b604f4e92e3f92dadd8")
    }
    func testCrossPlatformFrameAndBounds() throws {
        let vector = try XCTUnwrap(Data(hex: "0201020304c59fc49ff09f9880"))
        guard case .bytes(let sequence, let data) = try NearbyBleProtocol.decode(vector) else { return XCTFail() }
        XCTAssertEqual(sequence, 0x01020304); XCTAssertEqual(String(data: data, encoding: .utf8), "şğ😀")
        XCTAssertEqual(try NearbyBleProtocol.encode(.bytes(sequence, data)), vector)
        for bytes in [
            Data(), Data([3, 0, 0, 0]), Data([3, 0, 0, 0, 0, 0]), Data([2, 0, 0, 0, 0]), Data([4, 0, 0, 0, 0]),
            Data([2, 0, 0, 0, 0]) + Data(repeating: 0, count: 8193),
        ] {
            XCTAssertThrowsError(try NearbyBleProtocol.decode(bytes))
        }
        XCTAssertThrowsError(try NearbyBleProtocol.encode(.bytes(0, Data(repeating: 0, count: 8193))))
        guard case .acknowledgement(let ack) = try NearbyBleProtocol.decode(Data([3, 255, 255, 255, 255])) else {
            return XCTFail()
        }
        XCTAssertEqual(ack, UInt32.max)
    }
}
