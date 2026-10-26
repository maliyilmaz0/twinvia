import AndrofestProtocol
import Foundation
import XCTest
@testable import Androfest

final class NotificationDeliveryStateTests: XCTestCase {
    private func value(text: String = "Mesaj", time: Int64 = 100, replay: Bool = false, token: String? = nil) throws
        -> NotificationPosted
    {
        var object: [String: Any] = [
            "key": "chat:1", "packageName": "test.chat", "appName": "Chat",
            "title": "Sohbet", "text": text, "postedAt": time, "canReply": true, "isReplay": replay,
        ]
        if let token { object["actionToken"] = token }
        return try JSONDecoder().decode(NotificationPosted.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testReconnectSnapshotsAndTokenChangesDoNotAlertAgain() throws {
        var state = NotificationDeliveryState()
        XCTAssertTrue(state.record(try value()).alert)
        for _ in 0..<20 {
            let decision = state.record(try value(replay: true, token: UUID().uuidString))
            XCTAssertFalse(decision.changed); XCTAssertFalse(decision.alert)
        }
        XCTAssertFalse(state.record(try value(token: UUID().uuidString)).alert)
    }

    func testInitialSnapshotIsSilentButNewIdenticalTextMessageAlerts() throws {
        var state = NotificationDeliveryState()
        XCTAssertFalse(state.record(try value(replay: true)).alert)
        XCTAssertFalse(state.record(try value()).alert)
        XCTAssertTrue(state.record(try value(time: 101)).alert)
        XCTAssertTrue(state.record(try value(text: "Yeni içerik", time: 101)).alert)
        state.remove("chat:1")
        XCTAssertTrue(state.record(try value()).alert)
    }
}
