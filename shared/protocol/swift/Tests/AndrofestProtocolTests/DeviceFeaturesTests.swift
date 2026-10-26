import Foundation
import XCTest
@testable import AndrofestProtocol

final class DeviceFeaturesTests: XCTestCase {
    private let id = "12345678-1234-1234-1234-123456789abc"
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("fixtures/" + name + ".json"))
    }
    func testSharedFixturesDecodeAndRoundTrip() throws {
        let call = try WireCodec.decode(DeviceStatus.self, from: fixture("device-status-call"))
        XCTAssertEqual(call.payload.call?.state, "active")
        XCTAssertNotNil(try WireCodec.decode(DeviceStatus.self, from: WireCodec.encode(call)).payload.call?.approval)
        let command = try WireCodec.decode(DeviceCommand.self, from: fixture("device-command"))
        XCTAssertEqual(command.payload.action, .notificationReply)
        XCTAssertEqual(
            try WireCodec.decode(DeviceCommand.self, from: WireCodec.encode(command)).payload.text, "Merhaba 👋")
        XCTAssertTrue(try WireCodec.decode(CommandResult.self, from: fixture("command-result")).payload.success)
        XCTAssertEqual(
            try WireCodec.decode(DeviceStatus.self, from: fixture("device-status")).payload.batteryPercent, 72)
        XCTAssertEqual(
            try WireCodec.decode(SharedText.self, from: fixture("shared-text")).payload.text, "Mac ve Android 👋")
        XCTAssertNil(try WireCodec.decode(SharedText.self, from: fixture("shared-text")).payload.isClipboard)
        let clip = try WireCodec.decode(SharedText.self, from: fixture("clipboard-text"))
        XCTAssertEqual(try WireCodec.decode(SharedText.self, from: WireCodec.encode(clip)).payload.isClipboard, true)
    }
    func testPhonePagesShareTheSameWireFormat() throws {
        for kind in ["contacts", "calls", "files"] {
            let page = try WireCodec.decode(CommandResult.self, from: fixture("phone-" + kind))
            XCTAssertEqual(page.payload.data?.kind.rawValue, kind)
            _ = try WireCodec.decode(CommandResult.self, from: WireCodec.encode(page))
        }
        for path in ["../secret", "/data/data", "x/../secret", "x/./y"] {
            XCTAssertThrowsError(try DeviceCommand(action: .filesList, browse: PhoneQuery(path: path)).validate())
        }
        XCTAssertThrowsError(try DeviceCommand(action: .contactsList, browse: PhoneQuery(offset: -1)).validate())
    }
    func testNotificationActionsRequireFreshReferenceAndBoundedText() {
        for value in [
            DeviceCommand(action: .notificationReply, text: "hello", key: "key"),
            DeviceCommand(action: .notificationReply, text: " ", key: "key", actionToken: id),
            DeviceCommand(
                action: .notificationReply, text: String(repeating: "a", count: 4097), key: "key", actionToken: id),
            DeviceCommand(action: .notificationDismiss, text: "extra", key: "key", actionToken: id),
            DeviceCommand(action: .ring, key: "extra"),
        ] {
            XCTAssertThrowsError(try value.validate())
        }
    }
    func testAllControlActionsAndUnicodeSizeBoundary() throws {
        for action in [DeviceAction.ring, .stopRinging, .mediaNext, .mediaPrevious, .mediaPlayPause] {
            try DeviceCommand(action: action).validate()
        }
        try DeviceCommand(action: .clipboardSet, text: String(repeating: "👋", count: 8192)).validate()
        XCTAssertThrowsError(
            try DeviceCommand(action: .clipboardSet, text: String(repeating: "👋", count: 8193)).validate())
        XCTAssertThrowsError(try DeviceStatus(batteryPercent: 101, charging: false, locked: false).validate())
        XCTAssertThrowsError(try CommandResult(requestId: "bad", success: true, message: "ok").validate())
    }
    func testCallActionsRequireCallReferenceAndStatusRejectsInvalidConsent() throws {
        for action in [DeviceAction.callAnswerMac, .callHandoffApprove, .callEnd] {
            XCTAssertThrowsError(try DeviceCommand(action: action).validate())
            try DeviceCommand(action: action, actionToken: id).validate()
            XCTAssertThrowsError(try DeviceCommand(action: action, text: "unexpected", actionToken: id).validate())
        }
        XCTAssertThrowsError(try PhoneCallState(state: "idle", token: id, approval: id).validate())
        XCTAssertThrowsError(try PhoneCallState(state: "active", approval: id).validate())
        XCTAssertThrowsError(try PhoneCallState(state: "active", token: id, approval: "bad").validate())
    }

}
