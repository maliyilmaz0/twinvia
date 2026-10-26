import UserNotifications

/// Project SDK objects into Sendable values inside their callbacks. Older SDKs do not
/// mark UNNotificationSettings or UNNotification as Sendable; neither leaves this boundary.
@MainActor
enum NotificationCenterSnapshot {
    static func authorizationStatus() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
                continuation.resume(returning: settings.authorizationStatus.rawValue)
            }
        }
    }

    static func deliveredIdentifiers(for packageName: String) async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { @Sendable notifications in
                let identifiers = notifications.filter {
                    $0.request.content.userInfo["packageName"] as? String == packageName
                }.map { $0.request.identifier }
                continuation.resume(returning: identifiers)
            }
        }
    }
}
