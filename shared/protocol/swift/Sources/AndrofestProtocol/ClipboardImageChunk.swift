import Foundation

/// ACI1 | UUID(16) | offset u32 | total u32 | SHA-256(32) | PNG bytes.
public struct ClipboardImageChunk: Sendable {
    public static let maxImageBytes = 20 * 1024 * 1024
    public static let maxChunkBytes = 65_536
    public let id: String
    public let offset: Int
    public let total: Int
    public let sha256: Data
    public let data: Data
    public init(id: String, offset: Int, total: Int, sha256: Data, data: Data) {
        self.id = id; self.offset = offset; self.total = total; self.sha256 = sha256; self.data = data
    }
    public func encode() throws -> Data {
        guard let uuid = UUID(uuidString: id), (1...Self.maxImageBytes).contains(total),
            offset >= 0, offset < total, (1...Self.maxChunkBytes).contains(data.count),
            data.count <= total - offset, sha256.count == 32
        else { throw ProtocolError.invalidPayload }
        var result = Data("ACI1".utf8), value = uuid.uuid
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        for number in [offset, total] {
            var encoded = UInt32(number).bigEndian
            withUnsafeBytes(of: &encoded) { result.append(contentsOf: $0) }
        }
        result.append(sha256); result.append(data)
        return result
    }
}
