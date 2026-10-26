import CryptoKit
import Foundation

public struct PairingInvitation: Codable, Sendable {
    public let version: Int
    public let id: String
    public let deviceId: String
    public let name: String
    public let host: String?
    public let port: Int?
    public let secret: String

    public let expiresAt: Int64

    public init(deviceId: String, name: String, host: String, port: Int, now: Int64 = epochMilliseconds()) {
        self.version = 1
        self.id = UUID().uuidString.lowercased()
        self.deviceId = deviceId
        self.name = String(name.prefix(128))
        self.host = host
        self.port = port
        self.secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).hex }
        self.expiresAt = now + 300_000
    }

    /// Address-free invitation for direct NAN discovery. Version 1 remains
    /// decodable solely to reuse previously stored trusted associations.
    public init(deviceId: String, name: String, now: Int64 = epochMilliseconds()) {
        self.version = 2
        self.id = UUID().uuidString.lowercased()
        self.deviceId = deviceId
        self.name = String(name.prefix(128))
        self.host = nil
        self.port = nil
        self.secret = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0).hex }
        self.expiresAt = now + 300_000
    }

    public func validate(now: Int64 = epochMilliseconds(), allowExpired: Bool = false) throws {
        let parts = (host ?? "").split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        let legacyEndpoint =
            version == 1 && port.map { (1024...65535).contains($0) } == true && parts.count == 4
            && parts.allSatisfy({ (0...255).contains($0) })
            && (parts[0] == 10 || (parts[0] == 172 && (16...31).contains(parts[1]))
                || (parts[0] == 192 && parts[1] == 168))
        let direct = version == 2 && host == nil && port == nil
        guard legacyEndpoint || direct, UUID(uuidString: id) != nil, UUID(uuidString: deviceId) != nil,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 128,
            Data(hex: secret)?.count == 32, secret == secret.lowercased(), expiresAt > 0
        else { throw ProtocolError.invalidPayload }
        if !allowExpired && !(expiresAt > now && expiresAt <= now + 315_000) { throw ProtocolError.invalidPayload }
    }

    public func link() throws -> String {
        try validate()
        return "androfest://pair?data=" + (try JSONEncoder().encode(self)).base64URL
    }
}

public struct PairingIntroduction: Codable, Sendable {
    public let version: Int
    public let invitationId: String
    public let deviceId: String
    public let name: String
    public let port: Int
    public let fingerprint: String
    public let nonce: String
    public let timestamp: Int64
    public let proof: String

    public var authenticatedText: String {
        [
            "androfest.introduction.v1", invitationId, deviceId, Data(name.utf8).base64URL,
            String(port), fingerprint, nonce, String(timestamp),
        ].joined(separator: "\n")
    }

    public func verify(invitation: PairingInvitation, now: Int64 = epochMilliseconds()) -> Bool {
        guard version == 1, invitationId == invitation.id, UUID(uuidString: deviceId) != nil,
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf16.count <= 128,
            (1024...65535).contains(port), Data(hex: fingerprint)?.count == 32,
            fingerprint == fingerprint.lowercased(), Data(hex: nonce)?.count == 16,
            nonce == nonce.lowercased(), timestamp >= now - 90_000, timestamp <= now + 90_000,
            let key = Data(hex: invitation.secret), let signature = Data(hex: proof), signature.count == 32,
            proof == proof.lowercased()
        else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(
            signature, authenticating: Data(authenticatedText.utf8), using: SymmetricKey(data: key))
    }
}

public struct SessionAuthentication: Encodable, Sendable {
    public let kind = "session.auth"
    public let version = 1
    public let invitationId: String
    public let deviceId: String
    public let secret: String
    public let capabilities: [String]

    public init(invitation: PairingInvitation) {
        self.invitationId = invitation.id
        self.deviceId = invitation.deviceId
        self.secret = invitation.secret
        self.capabilities = [
            "device.status", "text.share", "device.commands", "notifications.actions", "clipboard.sync", "phone.browse",
        ]
    }
}

public func epochMilliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

public extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
            append(byte)
            index = end
        }
    }
}
