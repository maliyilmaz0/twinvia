import AndrofestProtocol
import CryptoKit
import Foundation

/// Revision identity ignores wire IDs, replay flags, icons and action tokens.
/// Only hashes live in this bounded, in-memory cache.
struct NotificationDeliveryState {
    struct Decision { let changed: Bool; let alert: Bool; let revision: String }
    private var revisions: [String: String] = [:]
    private var order: [String] = []

    mutating func record(_ value: NotificationPosted) -> Decision {
        struct Visible: Encodable {
            let packageName: String; let appName: String; let title: String?; let text: String?; let postedAt: Int64
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let visible = Visible(
            packageName: value.packageName, appName: value.appName,
            title: value.title, text: value.text, postedAt: value.postedAt)
        let bytes = (try? encoder.encode(visible)) ?? Data()
        let revision = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let changed = revisions[value.key] != revision
        revisions[value.key] = revision
        order.removeAll { $0 == value.key }; order.append(value.key)
        if order.count > 512 { revisions.removeValue(forKey: order.removeFirst()) }
        return Decision(changed: changed, alert: changed && value.isReplay != true, revision: revision)
    }

    mutating func remove(_ key: String) { revisions.removeValue(forKey: key); order.removeAll { $0 == key } }
}
