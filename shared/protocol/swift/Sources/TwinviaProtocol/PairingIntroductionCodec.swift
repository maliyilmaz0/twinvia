import Foundation

/// Compact pairing introduction carried by the BLE transport.
public enum PairingIntroductionCodec {
    /// AFN1 is the existing compact introduction wire format; retain its bytes for compatibility.
    public static func decodeIntroduction(_ data: Data, invitationID: String) throws -> PairingIntroduction {
        let bytes = Array(data)
        guard bytes.count >= 111, bytes.count <= 175, bytes.prefix(4).elementsEqual("AFN1".utf8) else {
            throw ProtocolError.invalidPayload
        }
        let nameLength = Int(bytes[78])
        guard (1...64).contains(nameLength), bytes.count == 111 + nameLength,
            let name = String(bytes: bytes[79..<(79 + nameLength)], encoding: .utf8)
        else { throw ProtocolError.invalidPayload }
        let id = Data(bytes[4..<20]).hex
        let uuid =
            "\(id.prefix(8))-\(id.dropFirst(8).prefix(4))-\(id.dropFirst(12).prefix(4))-\(id.dropFirst(16).prefix(4))-\(id.suffix(12))"
        let timestamp = bytes[70..<78].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard timestamp <= UInt64(Int64.max) else { throw ProtocolError.invalidPayload }
        return PairingIntroduction(
            version: 1, invitationId: invitationID, deviceId: uuid, name: name,
            port: Int(bytes[20]) << 8 | Int(bytes[21]), fingerprint: Data(bytes[22..<54]).hex,
            nonce: Data(bytes[54..<70]).hex, timestamp: Int64(timestamp),
            proof: Data(bytes[(79 + nameLength)...]).hex)
    }
}
