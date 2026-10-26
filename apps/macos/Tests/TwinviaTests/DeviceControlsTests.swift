import TwinviaProtocol
import XCTest
@testable import Twinvia

@MainActor
final class DeviceControlsTests: XCTestCase {
    func testOnlyMatchingAcknowledgementAllowsNextCommand() {
        let id = "12345678-1234-1234-1234-123456789abc"
        var sent = 0
        let controls = DeviceControls { _ in
            sent += 1; return id
        }
        controls.perform(DeviceCommand(action: .ring))
        XCTAssertTrue(controls.busy)
        controls.perform(DeviceCommand(action: .ring))
        XCTAssertEqual(sent, 1)
        controls.receive(CommandResult(requestId: UUID().uuidString, success: true, message: "wrong"))
        XCTAssertTrue(controls.busy)
        controls.receive(CommandResult(requestId: id, success: false, message: "İzin kapalı"))
        XCTAssertFalse(controls.busy)
        XCTAssertEqual(controls.message, "İzin kapalı")
        controls.perform(DeviceCommand(action: .stopRinging))
        XCTAssertEqual(sent, 2)
        controls.disconnected()
    }

    func testDisconnectDoesNotRetryOrAcceptLateSuccess() {
        let id = UUID().uuidString
        var sent = 0
        let controls = DeviceControls { _ in
            sent += 1; return id
        }
        controls.perform(
            DeviceCommand(action: .notificationReply, text: "Test", key: "key", actionToken: UUID().uuidString))
        controls.disconnected()
        let message = controls.message
        controls.receive(CommandResult(requestId: id, success: true, message: "success"))
        XCTAssertEqual(sent, 1)
        XCTAssertFalse(controls.busy)
        XCTAssertEqual(controls.message, message)
    }
}
