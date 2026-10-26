import Foundation
import XCTest
@testable import TwinviaProtocol

final class PairingProtocolTests: XCTestCase {
    private struct Fixture: Decodable {
        let invitation: PairingInvitation
        let introduction: PairingIntroduction
        let link: String
    }
    private let now: Int64 = 1792188000000
    private func fixture() throws -> Fixture {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/pairing/handshake.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: directory))
    }

    func testIndependentlyGeneratedHMACFixtureAuthenticates() throws {
        let f = try fixture()
        try f.invitation.validate(now: now)
        XCTAssertTrue(f.introduction.verify(invitation: f.invitation, now: now))
    }

    func testEndpointOrCertificateTamperingRejected() throws {
        let f = try fixture()
        let data = try JSONEncoder().encode(f.introduction)
        for (key, value): (String, Any) in [
            ("port", 12345), ("fingerprint", String(repeating: "d4", count: 32)), ("deviceId", f.invitation.deviceId),
        ] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object[key] = value
            let changed = try JSONDecoder().decode(
                PairingIntroduction.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertFalse(changed.verify(invitation: f.invitation, now: now))
        }
    }

    func testWrongSecretAndStaleIntroductionsRejected() throws {
        let f = try fixture()
        let other = PairingInvitation(
            deviceId: f.invitation.deviceId, name: f.invitation.name, host: try XCTUnwrap(f.invitation.host),
            port: try XCTUnwrap(f.invitation.port), now: now)
        XCTAssertFalse(f.introduction.verify(invitation: other, now: now))
        XCTAssertFalse(f.introduction.verify(invitation: f.invitation, now: now + 90_001))
        XCTAssertFalse(f.introduction.verify(invitation: f.invitation, now: now - 90_001))
    }

    func testExpiredQRRejectedForNewPairing() throws {
        let f = try fixture()
        XCTAssertThrowsError(try f.invitation.validate(now: now + 300_001))
        try f.invitation.validate(now: now + 300_001, allowExpired: true)
    }

    func testPublicNetworkDestinationRejected() {
        let invitation = PairingInvitation(
            deviceId: UUID().uuidString, name: "Mac", host: "8.8.8.8", port: 39873, now: now)
        XCTAssertThrowsError(try invitation.validate(now: now))
    }

    func testCompactIntroductionMatchesIndependentVector() throws {
        struct Vector: Decodable { let compactIntroduction: String }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/pairing/native-peer.json")
        let vector = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
        let f = try fixture()
        let wire = try XCTUnwrap(Data(base64Encoded: vector.compactIntroduction))
        let decoded = try PairingIntroductionCodec.decodeIntroduction(wire, invitationID: f.invitation.id)
        XCTAssertTrue(decoded.verify(invitation: f.invitation, now: now))
        XCTAssertEqual(decoded.authenticatedText, f.introduction.authenticatedText)
        for length in 0..<wire.count {
            XCTAssertThrowsError(
                try PairingIntroductionCodec.decodeIntroduction(
                    Data(wire.prefix(length)), invitationID: f.invitation.id))
        }
        XCTAssertThrowsError(
            try PairingIntroductionCodec.decodeIntroduction(wire + Data([0]), invitationID: f.invitation.id))
        var tampered = wire; tampered[21] ^= 1
        let changed = try PairingIntroductionCodec.decodeIntroduction(tampered, invitationID: f.invitation.id)
        XCTAssertFalse(changed.verify(invitation: f.invitation, now: now))
    }

    func testAddressFreePairingAndDiscoveryIsolation() throws {
        struct Vector: Decodable {
            let invitation: PairingInvitation; let introduction: PairingIntroduction
            let link: String; let compactIntroduction: String
        }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/pairing/native-pairing.json")
        let f = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
        try f.invitation.validate(now: now)
        XCTAssertNil(f.invitation.host); XCTAssertNil(f.invitation.port)
        XCTAssertEqual(f.invitation.version, 2)
        XCTAssertTrue(f.introduction.verify(invitation: f.invitation, now: now))
        let decoded = try PairingIntroductionCodec.decodeIntroduction(
            XCTUnwrap(Data(base64Encoded: f.compactIntroduction)), invitationID: f.invitation.id)
        XCTAssertTrue(decoded.verify(invitation: f.invitation, now: now))
        XCTAssertThrowsError(try f.invitation.validate(now: now + 300_001))
        try f.invitation.validate(now: now + 300_001, allowExpired: true)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(f.invitation)) as? [String: Any])
        object["host"] = "192.168.1.1"; object["port"] = 45311
        let injected = try JSONDecoder().decode(
            PairingInvitation.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try injected.validate(now: now))
        let fresh = PairingInvitation(deviceId: f.invitation.deviceId, name: "Mac", now: now)
        try fresh.validate(now: now)
        XCTAssertFalse(f.introduction.verify(invitation: fresh, now: now))
    }
}
