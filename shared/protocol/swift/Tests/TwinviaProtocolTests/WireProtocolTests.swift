import Foundation
import XCTest
@testable import TwinviaProtocol

final class WireProtocolTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures")
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }

    private func altered(_ name: String, _ update: (inout [String: Any]) -> Void) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(name)) as? [String: Any])
        update(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testAllSharedFixturesRoundTrip() throws {
        func roundTrip<T: WirePayload>(_ type: T.Type, _ name: String) throws {
            let envelope = try WireCodec.decode(type, from: fixture(name))
            let decoded = try WireCodec.decode(type, from: WireCodec.encode(envelope))
            XCTAssertEqual(decoded.id, envelope.id)
            XCTAssertEqual(decoded.type, envelope.type)
        }
        try roundTrip(DeviceHello.self, "device-hello.json")
        try roundTrip(NotificationPosted.self, "notification-posted.json")
        try roundTrip(NotificationPosted.self, "notification-replay.json")
        let replay = try WireCodec.decode(NotificationPosted.self, from: fixture("notification-replay.json"))
        XCTAssertEqual(
            try WireCodec.decode(NotificationPosted.self, from: WireCodec.encode(replay)).payload.isReplay, true)
        XCTAssertNil(
            try WireCodec.decode(NotificationPosted.self, from: fixture("notification-posted.json")).payload.isReplay)
        try roundTrip(NotificationRemoved.self, "notification-removed.json")
        try roundTrip(FileOffer.self, "file-offer.json")
        try roundTrip(FileAccept.self, "file-accept.json")
        try roundTrip(FileComplete.self, "file-complete.json")
        try roundTrip(FileCancel.self, "file-cancel.json")
    }

    func testUnicodeNotificationContentSurvives() throws {
        let envelope = try WireCodec.decode(NotificationPosted.self, from: fixture("notification-posted.json"))
        XCTAssertEqual(envelope.payload.text, "Merhaba Mac 👋")
    }

    func testNotificationIconIsBackwardCompatible() throws {
        let previous = try WireCodec.decode(NotificationPosted.self, from: fixture("notification-posted.json"))
        XCTAssertNil(previous.payload.appIconPng)
        let rich = try WireCodec.decode(NotificationPosted.self, from: fixture("notification-with-icon.json"))
        XCTAssertNotNil(rich.payload.appIconPng)
        XCTAssertEqual(
            try WireCodec.decode(NotificationPosted.self, from: WireCodec.encode(rich)).payload.appIconPng,
            rich.payload.appIconPng)
    }

    func testMalformedAndOversizedIconsRejected() throws {
        for value in [
            "not base64", Data(repeating: 0, count: 24).base64EncodedString(), String(repeating: "A", count: 87_388),
        ] {
            let data = try altered("notification-posted.json") {
                var payload = $0["payload"] as! [String: Any]
                payload["appIconPng"] = value
                $0["payload"] = payload
            }
            XCTAssertThrowsError(try WireCodec.decode(NotificationPosted.self, from: data))
        }
    }

    func testUnsupportedVersionRejected() throws {
        let data = try altered("device-hello.json") { $0["version"] = 2 }
        XCTAssertThrowsError(try WireCodec.decode(DeviceHello.self, from: data))
    }

    func testUnknownMessageTypeRejected() throws {
        let data = try altered("device-hello.json") { $0["type"] = "command.execute" }
        XCTAssertThrowsError(try WireCodec.decode(DeviceHello.self, from: data))
    }

    func testMismatchedPayloadTypeRejected() throws {
        let data = try altered("device-hello.json") { $0["type"] = "file.offer" }
        XCTAssertThrowsError(try WireCodec.decode(DeviceHello.self, from: data))
    }

    func testInvalidDeviceIDRejected() throws {
        let data = try altered("device-hello.json") { $0["sourceDeviceId"] = "not-a-uuid" }
        XCTAssertThrowsError(try WireCodec.decode(DeviceHello.self, from: data))
    }

    func testMissingRequiredPayloadRejected() throws {
        let data = try altered("file-offer.json") { $0["payload"] = [:] as [String: String] }
        XCTAssertThrowsError(try WireCodec.decode(FileOffer.self, from: data))
    }

    func testUnsafeFileNamesRejected() throws {
        for name in ["../secret", "folder/file.txt", "folder\\file.txt", "..", ".", "bad\0name", " "] {
            let data = try altered("file-offer.json") {
                var payload = $0["payload"] as! [String: Any]
                payload["fileName"] = name
                $0["payload"] = payload
            }
            XCTAssertThrowsError(try WireCodec.decode(FileOffer.self, from: data))
        }
    }

    func testInvalidHashAndNegativeLengthRejected() throws {
        for (key, value): (String, Any) in [
            ("sha256", "bad"), ("sha256", String(repeating: "a", count: 64) + "\n"), ("size", -1),
        ] {
            let data = try altered("file-offer.json") {
                var payload = $0["payload"] as! [String: Any]
                payload[key] = value
                $0["payload"] = payload
            }
            XCTAssertThrowsError(try WireCodec.decode(FileOffer.self, from: data))
        }
    }

    func testOversizeControlMessageRejectedBeforeDecoding() {
        XCTAssertThrowsError(
            try WireCodec.decode(DeviceHello.self, from: Data(repeating: 32, count: WireCodec.maxMessageBytes + 1)))
    }

    func testNegativeResumeOffsetRejected() throws {
        let data = try altered("file-accept.json") {
            var payload = $0["payload"] as! [String: Any]
            payload["offset"] = -1
            $0["payload"] = payload
        }
        XCTAssertThrowsError(try WireCodec.decode(FileAccept.self, from: data))
    }

    func testAdditiveFieldsAllowed() throws {
        let data = try altered("device-hello.json") { $0["futureField"] = true }
        XCTAssertEqual(try WireCodec.decode(DeviceHello.self, from: data).type, .deviceHello)
    }
}
