import AndrofestProtocol
import CryptoKit
import Foundation
import UserNotifications

@MainActor
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    #if DEBUG
        private(set) static var diagnostics = ["scheduled": 0, "replaySuppressed": 0, "duplicateSuppressed": 0]
    #endif
    var onError: ((String) -> Void)?
    var onSent: (() -> Void)?
    var onAction: ((DeviceCommand) -> Void)?
    var onCallAction: ((String, String) -> Void)?
    private var incomingCallID: String?
    private var deliveryTokens: [String: UUID] = [:]
    private var deliveries: [String: (id: UUID, task: Task<Void, Never>)] = [:]
    private var deliveryState = NotificationDeliveryState()
    private var latestActions: [String: (revision: String, token: String)] = [:]
    var mutedPackages = Set<String>()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: "reply", title: "Reply", options: [.authenticationRequired], textInputButtonTitle: "Send",
            textInputPlaceholder: "Write your reply")
        let dismiss = UNNotificationAction(
            identifier: "dismiss-phone", title: "Dismiss on phone", options: [.authenticationRequired])
        let answerCall = UNNotificationAction(
            identifier: "answer-call", title: "Answer on Mac", options: [.authenticationRequired, .foreground])
        let declineCall = UNNotificationAction(
            identifier: "decline-call", title: "Decline", options: [.authenticationRequired, .destructive])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: "phone-call", actions: [answerCall, declineCall], intentIdentifiers: []),
            UNNotificationCategory(
                identifier: "android-reply-dismiss", actions: [reply, dismiss], intentIdentifiers: []),
            UNNotificationCategory(identifier: "android-reply", actions: [reply], intentIdentifiers: []),
            UNNotificationCategory(identifier: "android-dismiss", actions: [dismiss], intentIdentifiers: []),
        ])
    }

    @discardableResult
    func enqueue(_ notification: NotificationPosted) -> Task<Void, Never> {
        let decision = deliveryState.record(notification)
        if let actionToken = notification.actionToken {
            latestActions[notification.key] = (decision.revision, actionToken)
            if latestActions.count > 512, let key = latestActions.keys.first { latestActions.removeValue(forKey: key) }
        } else {
            latestActions.removeValue(forKey: notification.key)
        }
        guard decision.alert else {
            #if DEBUG
                Self.diagnostics[
                    notification.isReplay == true ? "replaySuppressed" : "duplicateSuppressed", default: 0] += 1
            #endif
            if decision.changed {
                deliveryTokens.removeValue(forKey: notification.key)
                deliveries[notification.key]?.task.cancel()
            }
            return Task {}
        }
        let key = notification.key, token = UUID()
        let previous = deliveries[key]?.task
        previous?.cancel()
        deliveryTokens[key] = token
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            if !Task.isCancelled { await self.deliver(notification, token: token, revision: decision.revision) }
            if self.deliveries[key]?.id == token { self.deliveries.removeValue(forKey: key) }
            if self.deliveryTokens[key] == token { self.deliveryTokens.removeValue(forKey: key) }
        }
        deliveries[key] = (token, task)
        return task
    }

    func post(_ notification: NotificationPosted) async { await enqueue(notification).value }

    private func deliver(_ notification: NotificationPosted, token: UUID, revision: String) async {
        guard deliveryTokens[notification.key] == token, !Task.isCancelled,
            !mutedPackages.contains(notification.packageName)
        else { return }
        let center = UNUserNotificationCenter.current()
        let authorization = await NotificationCenterSnapshot.authorizationStatus()
        guard deliveryTokens[notification.key] == token, !Task.isCancelled,
            !mutedPackages.contains(notification.packageName)
        else { return }
        guard NotificationAuthorization.allowsDelivery(authorization) else {
            onError?("Click 'Allow' in Notifications to enable Mac notification permission.")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notification.appName
        content.subtitle = notification.title ?? ""
        content.body = notification.text ?? ""
        content.sound = .default
        content.threadIdentifier = Self.identifier(notification.packageName)
        content.userInfo = [
            "packageName": notification.packageName, "notificationKey": notification.key, "revision": revision,
        ]
        if let token = notification.actionToken {
            content.userInfo["actionToken"] = token
            if notification.canReply {
                content.categoryIdentifier = notification.canDismiss == true ? "android-reply-dismiss" : "android-reply"
            } else if notification.canDismiss == true {
                content.categoryIdentifier = "android-dismiss"
            }
        }
        var directory: URL?
        do {
            if let encoded = notification.appIconPng, let png = Data(base64Encoded: encoded) {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                    UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                directory = folder
                let file = folder.appendingPathComponent("app-icon.png")
                try png.write(to: file, options: .atomic)
                if let attachment = try? UNNotificationAttachment(
                    identifier: "android-app-icon", url: file,
                    options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false])
                {
                    content.attachments = [attachment]
                }
            }
            // UserNotifications copies attachments into its own storage before add returns.
            defer { if let directory { try? FileManager.default.removeItem(at: directory) } }
            try await center.add(
                UNNotificationRequest(identifier: Self.identifier(notification.key), content: content, trigger: nil))
            if deliveryTokens[notification.key] != token || Task.isCancelled
                || mutedPackages.contains(notification.packageName)
            {
                center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(notification.key)])
            } else {
                #if DEBUG
                    Self.diagnostics["scheduled", default: 0] += 1
                #endif
                onSent?()
            }
        } catch {
            if let directory { try? FileManager.default.removeItem(at: directory) }
            onError?("Could not show the Mac notification: \(error.localizedDescription)")
        }
    }

    func remove(_ key: String) {
        deliveryState.remove(key); latestActions.removeValue(forKey: key)
        deliveryTokens.removeValue(forKey: key)
        deliveries[key]?.task.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(key)])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier(key)])
    }

    func postIncomingCall(id: UUID, phone: String) async {
        let token = id.uuidString
        guard incomingCallID != token else { return }
        incomingCallID = token
        let center = UNUserNotificationCenter.current()
        let authorization = await NotificationCenterSnapshot.authorizationStatus()
        guard incomingCallID == token,
            NotificationAuthorization.allowsDelivery(authorization)
        else { return }
        let content = UNMutableNotificationContent()
        content.title = "Incoming call"
        content.body = "\(phone) · Answer on Mac or open the call screen."
        content.sound = .default
        content.categoryIdentifier = "phone-call"
        content.userInfo = ["callToken": token]
        let identifier = "androfest.call." + token
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        if incomingCallID != token { center.removeDeliveredNotifications(withIdentifiers: [identifier]) }
    }

    func removeIncomingCall() {
        guard let incomingCallID else { return }
        self.incomingCallID = nil
        let identifier = "androfest.call." + incomingCallID
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func removePackage(_ packageName: String) async {
        let center = UNUserNotificationCenter.current()
        let identifiers = await NotificationCenterSnapshot.deliveredIdentifiers(for: packageName)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated static func identifier(_ key: String) -> String {
        "androfest." + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let token = info["callToken"] as? String {
            let action = response.actionIdentifier
            await MainActor.run { self.onCallAction?(action, token) }
            return
        }
        guard let key = info["notificationKey"] as? String, let token = info["actionToken"] as? String else { return }
        let revision = info["revision"] as? String
        let action: DeviceAction
        let text: String?
        if response.actionIdentifier == "reply", let input = response as? UNTextInputNotificationResponse {
            action = .notificationReply; text = input.userText
        } else if response.actionIdentifier == "dismiss-phone" {
            action = .notificationDismiss; text = nil
        } else {
            return
        }
        let currentToken = await MainActor.run {
            guard let revision, let latest = self.latestActions[key], latest.revision == revision else { return token }
            return latest.token
        }
        let command = DeviceCommand(action: action, text: text, key: key, actionToken: currentToken)
        await MainActor.run { self.onAction?(command) }
    }
}
