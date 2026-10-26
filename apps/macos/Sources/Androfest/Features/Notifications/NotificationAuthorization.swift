import Foundation
import UserNotifications

/// Older SDKs do not make UNNotificationSettings Sendable. Read it inside the callback
/// and pass only an integer through the continuation; never transfer the settings object.
enum NotificationAuthorization {
    @MainActor
    static func currentStatus() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
    }

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
