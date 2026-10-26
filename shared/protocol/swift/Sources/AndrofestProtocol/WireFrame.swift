import Foundation

/// Four-byte network-order length framing for the authenticated TLS byte stream.
public enum WireFrame {
    public static let headerBytes = 4

    public static func payloadLength(_ header: Data) throws -> Int {
        guard header.count == headerBytes else { throw ProtocolError.invalidPayload }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length <= WireCodec.maxMessageBytes else { throw ProtocolError.invalidPayload }
        return Int(length)
    }

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= WireCodec.maxMessageBytes else { throw ProtocolError.invalidPayload }
        var length = UInt32(payload.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + payload
    }
}
