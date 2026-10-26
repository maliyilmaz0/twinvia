import TwinviaProtocol
import Foundation
import XCTest
@testable import Twinvia

final class BridgeEventTests: XCTestCase {
    private let source = "b82283ab-1934-467d-bb6d-a90fbb35083f"

    func testTypedTextAndCommandResultRouting() throws {
        let text = try WireCodec.encode(WireEnvelope(sourceDeviceId: source, payload: SharedText(text: "hello")))
        guard case .sharedText(let value) = try BridgeEvent.decode(text) else { return XCTFail("Wrong text route") }
        XCTAssertEqual(value.text, "hello")
        let result = CommandResult(requestId: UUID().uuidString, success: true, message: "ok")
        let data = try WireCodec.encode(WireEnvelope(sourceDeviceId: source, payload: result))
        guard case .commandResult(let decoded) = try BridgeEvent.decode(data) else {
            return XCTFail("Wrong result route")
        }
        XCTAssertEqual(decoded.requestId, result.requestId)
    }

    func testFileControlPreservesTransferIdentity() throws {
        let id = UUID().uuidString
        let data = try WireCodec.encode(WireEnvelope(sourceDeviceId: source, payload: FileCancel(transferId: id)))
        guard case .file(.cancel(let value)) = try BridgeEvent.decode(data) else { return XCTFail("Wrong file route") }
        XCTAssertEqual(value.transferId, id)
    }

    func testUnsupportedDirectionAndMalformedPayloadFailClosed() throws {
        let command = try WireCodec.encode(WireEnvelope(sourceDeviceId: source, payload: DeviceCommand(action: .ring)))
        XCTAssertThrowsError(try BridgeEvent.decode(command))
        let text = try WireCodec.encode(WireEnvelope(sourceDeviceId: source, payload: SharedText(text: "hello")))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: text) as? [String: Any])
        object["payload"] = ["text": 42]
        XCTAssertThrowsError(try BridgeEvent.decode(JSONSerialization.data(withJSONObject: object)))
    }
}
