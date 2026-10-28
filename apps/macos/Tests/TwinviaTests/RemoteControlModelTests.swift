import AppKit
import TwinviaProtocol
import XCTest
@testable import Twinvia

@MainActor
final class RemoteControlModelTests: XCTestCase {
    func testOnlyMatchingResultUnlocksNextActionAndDisconnectClearsScreen() {
        let id = UUID().uuidString
        var sent: [DeviceCommand] = []
        let model = RemoteControlModel { command in
            sent.append(command); return id
        }
        model.request(.remoteSnapshot)
        XCTAssertTrue(model.busy)
        model.request(.remoteHome)
        XCTAssertEqual(sent.count, 1)
        model.receive(CommandResult(requestId: UUID().uuidString, success: true, message: "Wrong"))
        XCTAssertTrue(model.busy)
        model.receive(CommandResult(requestId: id, success: false, message: "Start on phone"))
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.message, "Start on phone")
        model.tap(x: 0.5, y: 1.0)
        XCTAssertEqual(sent.last?.action, .remoteTap)
        XCTAssertEqual(sent.last?.key, "5000,10000")
        model.receive(CommandResult(requestId: id, success: false, message: "Stopped"))
        model.swipe(from: CGPoint(x: 0.5, y: 0.01), to: CGPoint(x: 0.5, y: 0.8))
        XCTAssertEqual(sent.last?.action, .remoteSwipe)
        XCTAssertEqual(sent.last?.key, "5000,100,5000,8000,300")
        model.disconnected()
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.image)
    }
}
