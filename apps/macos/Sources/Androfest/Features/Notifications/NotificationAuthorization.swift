import Foundation
import UserNotifications

/// Authorization policy shared by notification presentation and status UI.
enum NotificationAuthorization {
    static func allowsDelivery(_ status: Int) -> Bool {
        status == UNAuthorizationStatus.authorized.rawValue || status == UNAuthorizationStatus.provisional.rawValue
    }

    static func label(_ status: Int) -> String {
        switch status {
        case UNAuthorizationStatus.authorized.rawValue, UNAuthorizationStatus.provisional.rawValue:
            return "Notification permission enabled"
        case UNAuthorizationStatus.denied.rawValue:
            return "Notification permission disabled"
        case UNAuthorizationStatus.notDetermined.rawValue:
            return "Waiting for notification permission"
        default: return "Notification status unknown"
        }
    }
}
