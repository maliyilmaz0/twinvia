import AndrofestProtocol
import Foundation
import Security
import LocalAuthentication

struct TrustedPhone: Codable, Sendable {
    let invitation: PairingInvitation
    let deviceID: String
    let name: String
    let fingerprint: String
}

enum PeerKeychain {
    private nonisolated static let service = "dev.androfest.pairing.v1"

    nonisolated static func load(account: String, allowInteraction: Bool = false) throws -> TrustedPhone? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        if !allowInteraction {
            let context = LAContext(); context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext] = context
        }
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data else { throw KeychainError.failed(result) }
        let peer = try JSONDecoder().decode(TrustedPhone.self, from: data)
        try peer.invitation.validate(allowExpired: true)
        guard UUID(uuidString: peer.deviceID) != nil, Data(hex: peer.fingerprint)?.count == 32 else {
            throw ProtocolError.invalidPayload
        }
        return peer
    }

    static func save(_ peer: TrustedPhone, account: String) throws {
        let key: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
        ]
        let data = try JSONEncoder().encode(peer)
        let result = SecItemUpdate(key as CFDictionary, [kSecValueData: data] as CFDictionary)
        if result == errSecItemNotFound {
            var attributes = key
            attributes[kSecValueData] = data
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.failed(added) }
        } else if result != errSecSuccess {
            throw KeychainError.failed(result)
        }
    }

    static func remove(account: String) throws {
        let result = SecItemDelete(
            [
                kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                kSecAttrAccount: account,
            ] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw KeychainError.failed(result) }
    }
}

enum KeychainError: LocalizedError {
    case failed(OSStatus)
    var errorDescription: String? {
        "Keychain access is required. Click 'Allow pairing key access' and approve the system dialog."
    }
}
