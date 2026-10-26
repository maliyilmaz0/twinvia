import Foundation

/// Sendable because startup reads intentionally run away from MainActor and may prompt only on request.
protocol PeerTrustStore: Sendable {
    func load(account: String, allowInteraction: Bool) throws -> TrustedPhone?
    func save(_ peer: TrustedPhone, account: String) throws
    func remove(account: String) throws
}

struct KeychainPeerTrustStore: PeerTrustStore {
    func load(account: String, allowInteraction: Bool) throws -> TrustedPhone? {
        try PeerKeychain.load(account: account, allowInteraction: allowInteraction)
    }
    func save(_ peer: TrustedPhone, account: String) throws { try PeerKeychain.save(peer, account: account) }
    func remove(account: String) throws { try PeerKeychain.remove(account: account) }
}
