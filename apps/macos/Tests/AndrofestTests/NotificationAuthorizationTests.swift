import UserNotifications
import XCTest
@testable import Androfest

final class NotificationAuthorizationTests: XCTestCase {
    func testAuthorizedAndProvisionalStatesAllowDelivery() {
        for state in [UNAuthorizationStatus.authorized, .provisional] {
            XCTAssertTrue(NotificationAuthorization.allowsDelivery(state.rawValue))
            XCTAssertEqual(NotificationAuthorization.label(state.rawValue), "Notification permission enabled")
        }
    }

    func testDeniedUndeterminedAndFutureStatesFailClosed() {
        for status in [UNAuthorizationStatus.denied.rawValue, UNAuthorizationStatus.notDetermined.rawValue, -999] {
            XCTAssertFalse(NotificationAuthorization.allowsDelivery(status))
        }
        XCTAssertEqual(NotificationAuthorization.label(-999), "Notification status unknown")
        XCTAssertEqual(
            NotificationAuthorization.label(UNAuthorizationStatus.denied.rawValue), "Notification permission disabled")
    }
}
