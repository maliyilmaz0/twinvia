import CryptoKit
import Foundation

public struct RemoteChannel: Codable, Sendable {
    public let session: String
    public let key: String
    public static let serviceID = "c6175595-dfce-4e3f-a61b-ec9efb8c9ba2"
    public init(session: String, key: String) { self.session = session; self.key = key }
    public func validate() throws {
        guard key.count == 44, UUID(uuidString: session) != nil, let bytes = Data(base64Encoded: key), bytes.count == 32
        else {
            throw ProtocolError.invalidPayload
        }
    }
}
public struct FastScreenReply: Codable, Sendable {
    public let screen: RemoteScreen?
    public let error: String?
}

/// A session key travels only over the existing certificate-pinned channel.
/// Independent directional nonces and strict counters reject reflection and replay.
public struct RemoteFrameCipher {
    private let key: SymmetricKey
    private let session: Data
    private let sending: Data
    private let receiving: Data
    private var sent: UInt64 = 0
    private var received: UInt64 = 0
    public init(channel: RemoteChannel, mac: Bool) throws {
        try channel.validate()
        key = SymmetricKey(data: Data(base64Encoded: channel.key)!)
        session = Data(channel.session.utf8)
        sending = Data((mac ? "MAC0" : "AND0").utf8)
        receiving = Data((mac ? "AND0" : "MAC0").utf8)
    }
    public mutating func seal(_ plaintext: Data) throws -> Data {
        guard plaintext.count <= WireCodec.maxMessageBytes, sent < UInt64(Int64.max) else {
            throw ProtocolError.invalidPayload
        }
        let count = withUnsafeBytes(of: sent.bigEndian) { Data($0) }
        let nonce = try AES.GCM.Nonce(data: sending + count)
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: session + sending + count)
        sent += 1
        return count + box.ciphertext + box.tag
    }
    public mutating func open(_ bytes: Data) throws -> Data {
        guard (24...(WireCodec.maxMessageBytes + 24)).contains(bytes.count), received < UInt64(Int64.max) else {
            throw ProtocolError.invalidPayload
        }
        let count = Data(bytes.prefix(8))
        let number = count.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard number == received else { throw ProtocolError.invalidPayload }
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: receiving + count), ciphertext: bytes.dropFirst(8).dropLast(16),
            tag: bytes.suffix(16))
        let plaintext = try AES.GCM.open(box, using: key, authenticating: session + receiving + count)
        received += 1
        return plaintext
    }
}
