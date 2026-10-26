import CryptoKit
import Foundation

/// The Nearby link carries a pinned TLS byte stream, never plaintext app frames.
public enum NearbyBleProtocol {
    public static let maxChunk = 8192
    public static func serviceID(_ invitation: PairingInvitation) throws -> String {
        "dev.androfest.ble." + (try mac("service", invitation)).prefix(12).hex
    }
    public static func context(_ role: String, _ invitation: PairingInvitation) throws -> Data {
        guard role == "mac" || role == "phone" else { throw ProtocolError.invalidPayload }
        return (try mac("endpoint." + role, invitation)).prefix(16)
    }
    private static func mac(_ domain: String, _ invitation: PairingInvitation) throws -> Data {
        guard let key = Data(hex: invitation.secret), key.count == 32 else { throw ProtocolError.invalidPayload }
        return Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(("androfest.nearby.ble.v1." + domain + "\n" + invitation.id).utf8),
                using: SymmetricKey(data: key)))
    }
    public enum Packet {
        case introduction(Data)
        case bytes(UInt32, Data)
        case acknowledgement(UInt32)
    }
    public static func encode(_ packet: Packet) throws -> Data {
        switch packet {
        case .introduction(let data):
            guard (112...175).contains(data.count) else { throw ProtocolError.invalidPayload }
            return Data([1]) + data
        case .bytes(let sequence, let data):
            guard (1...maxChunk).contains(data.count) else { throw ProtocolError.invalidPayload }
            var value = sequence.bigEndian
            return Data([2]) + withUnsafeBytes(of: &value) { Data($0) } + data
        case .acknowledgement(let sequence):
            var value = sequence.bigEndian
            return Data([3]) + withUnsafeBytes(of: &value) { Data($0) }
        }
    }
    public static func decode(_ data: Data) throws -> Packet {
        let bytes = Array(data)
        guard let kind = bytes.first else { throw ProtocolError.invalidPayload }
        if kind == 1, (113...176).contains(bytes.count) { return .introduction(Data(bytes.dropFirst())) }
        guard bytes.count >= 5 else { throw ProtocolError.invalidPayload }
        let sequence = bytes[1...4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        if kind == 2, (6...(maxChunk + 5)).contains(bytes.count) { return .bytes(sequence, Data(bytes.dropFirst(5))) }
        if kind == 3, bytes.count == 5 { return .acknowledgement(sequence) }
        throw ProtocolError.invalidPayload
    }
}
