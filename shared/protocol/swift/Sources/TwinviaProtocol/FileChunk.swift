import Foundation

/// Binary payload inside the existing length-prefixed TLS frame.
/// AFC1 (4 bytes), RFC-4122 UUID (16), big-endian offset (8), data (1...16384).
public struct FileChunk: Sendable {
    public static let maxDataBytes = 16_384
    public static let maxFileBytes: Int64 = 2_147_483_648
    public let transferId: String
    public let offset: Int64
    public let data: Data

    public init(transferId: String, offset: Int64, data: Data) {
        self.transferId = transferId
        self.offset = offset
        self.data = data
    }

    public func encode() throws -> Data {
        guard let uuid = UUID(uuidString: transferId), offset >= 0, offset <= Self.maxFileBytes,
            (1...Self.maxDataBytes).contains(data.count)
        else { throw ProtocolError.invalidPayload }
        guard offset <= Self.maxFileBytes - Int64(data.count) else { throw ProtocolError.invalidPayload }
        var result = Data("AFC1".utf8)
        var identifier = uuid.uuid
        withUnsafeBytes(of: &identifier) { result.append(contentsOf: $0) }
        var position = UInt64(offset).bigEndian
        withUnsafeBytes(of: &position) { result.append(contentsOf: $0) }
        result.append(data)
        return result
    }

    public static func decode(_ frame: Data) throws -> FileChunk {
        guard frame.count > 28, frame.count <= 28 + maxDataBytes,
            frame.prefix(4) == Data("AFC1".utf8)
        else { throw ProtocolError.invalidPayload }
        let b = Array(frame[4..<20])
        let id = UUID(
            uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
        )
        let offset = frame[20..<28].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard offset <= UInt64(maxFileBytes) else { throw ProtocolError.invalidPayload }
        guard offset <= UInt64(maxFileBytes - Int64(frame.count - 28)) else { throw ProtocolError.invalidPayload }
        return FileChunk(transferId: id.uuidString.lowercased(), offset: Int64(offset), data: Data(frame.dropFirst(28)))
    }
}
