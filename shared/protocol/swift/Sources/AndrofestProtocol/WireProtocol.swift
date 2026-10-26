import Foundation

public enum MessageType: String, Codable, Sendable {
    case deviceHello = "device.hello"
    case notificationPosted = "notification.posted"
    case notificationRemoved = "notification.removed"
    case fileOffer = "file.offer"
    case fileAccept = "file.accept"
    case fileComplete = "file.complete"
    case fileCancel = "file.cancel"
    case deviceCommand = "device.command"
    case commandResult = "command.result"
    case deviceStatus = "device.status"
    case sharedText = "text.shared"
}

public enum ProtocolError: Error, Equatable {
    case invalidEnvelope
    case invalidPayload
    case messageTooLarge
}

public protocol WirePayload: Codable, Sendable {
    static var messageType: MessageType { get }
    func validate() throws
}

public struct WireEnvelope<Payload: WirePayload>: Codable, Sendable {
    public let version: Int
    public let id: String
    public let type: MessageType
    public let timestamp: Int64
    public let sourceDeviceId: String
    public let payload: Payload

    public init(sourceDeviceId: String, payload: Payload) {
        self.version = 1
        self.id = UUID().uuidString.lowercased()
        self.type = Payload.messageType
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        self.sourceDeviceId = sourceDeviceId
        self.payload = payload
    }

    public func validate() throws {
        guard version == 1, type == Payload.messageType,
            UUID(uuidString: id) != nil, UUID(uuidString: sourceDeviceId) != nil,
            timestamp > 0, timestamp <= 9_007_199_254_740_991
        else {
            throw ProtocolError.invalidEnvelope
        }
        try payload.validate()
    }
}

public enum WireCodec {
    public static let maxMessageBytes = 262_144

    public static func encode<T>(_ envelope: WireEnvelope<T>) throws -> Data {
        try envelope.validate()
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= maxMessageBytes else { throw ProtocolError.messageTooLarge }
        return data
    }

    public static func decode<T: WirePayload>(_ type: T.Type, from data: Data) throws -> WireEnvelope<T> {
        guard data.count <= maxMessageBytes else { throw ProtocolError.messageTooLarge }
        let envelope = try JSONDecoder().decode(WireEnvelope<T>.self, from: data)
        try envelope.validate()
        return envelope
    }
}

public struct DeviceHello: WirePayload {
    public static let messageType = MessageType.deviceHello
    public let name: String
    public let platform: String
    public let osVersion: String
    public let capabilities: [String]

    public init(name: String, platform: String, osVersion: String, capabilities: [String]) {
        self.name = name
        self.platform = platform
        self.osVersion = osVersion
        self.capabilities = capabilities
    }

    public func validate() throws {
        guard !name.isBlank, !osVersion.isBlank, ["android", "macos"].contains(platform),
            Set(capabilities).count == capabilities.count,
            capabilities.allSatisfy({ !$0.isBlank })
        else { throw ProtocolError.invalidPayload }
    }
}

public struct NotificationPosted: WirePayload {
    public static let messageType = MessageType.notificationPosted
    public let key: String
    public let packageName: String
    public let appName: String
    public let title: String?
    public let text: String?
    public let postedAt: Int64
    public let canReply: Bool
    public let appIconPng: String?
    public let actionToken: String?
    public let canDismiss: Bool?
    public let isReplay: Bool?

    public func validate() throws {
        guard !key.isBlank, !packageName.isBlank, !appName.isBlank,
            postedAt > 0, postedAt <= 9_007_199_254_740_991
        else { throw ProtocolError.invalidPayload }
        if let appIconPng {
            guard appIconPng.utf8.count <= 87_384,
                let png = Data(base64Encoded: appIconPng), png.count >= 24, png.count <= 65_536,
                png.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10])
            else { throw ProtocolError.invalidPayload }
            let width = png[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let height = png[20..<24].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard (1...256).contains(width), (1...256).contains(height) else { throw ProtocolError.invalidPayload }
        }
        if let actionToken, UUID(uuidString: actionToken) == nil { throw ProtocolError.invalidPayload }
    }
}

public struct NotificationRemoved: WirePayload {
    public static let messageType = MessageType.notificationRemoved
    public let key: String

    public func validate() throws {
        guard !key.isBlank else { throw ProtocolError.invalidPayload }
    }
}

public struct FileOffer: WirePayload {
    public static let messageType = MessageType.fileOffer
    public let transferId: String
    public let fileName: String
    public let mimeType: String
    public let size: Int64
    public let sha256: String

    public init(transferId: String, fileName: String, mimeType: String, size: Int64, sha256: String) {
        self.transferId = transferId
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.sha256 = sha256
    }

    public func validate() throws {
        guard UUID(uuidString: transferId) != nil,
            !fileName.isBlank, ![".", ".."].contains(fileName),
            !fileName.contains("/"), !fileName.contains("\\"),
            fileName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
            !mimeType.isBlank, size >= 0, size <= 9_007_199_254_740_991,
            sha256.isSHA256
        else {
            throw ProtocolError.invalidPayload
        }
    }
}

public struct FileAccept: WirePayload {
    public static let messageType = MessageType.fileAccept
    public let transferId: String
    public let offset: Int64

    public init(transferId: String, offset: Int64) {
        self.transferId = transferId
        self.offset = offset
    }

    public func validate() throws {
        guard UUID(uuidString: transferId) != nil, offset >= 0,
            offset <= 9_007_199_254_740_991
        else { throw ProtocolError.invalidPayload }
    }
}

public struct FileComplete: WirePayload {
    public static let messageType = MessageType.fileComplete
    public let transferId: String
    public let sha256: String

    public init(transferId: String, sha256: String) {
        self.transferId = transferId
        self.sha256 = sha256
    }

    public func validate() throws {
        guard UUID(uuidString: transferId) != nil,
            sha256.isSHA256
        else {
            throw ProtocolError.invalidPayload
        }
    }
}

public struct FileCancel: WirePayload {
    public static let messageType = MessageType.fileCancel
    public let transferId: String
    public let reason: String?

    public init(transferId: String, reason: String? = nil) { self.transferId = transferId; self.reason = reason }

    public func validate() throws {
        guard UUID(uuidString: transferId) != nil, (reason?.utf16.count ?? 0) <= 256 else {
            throw ProtocolError.invalidPayload
        }
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isSHA256: Bool {
        utf8.count == 64 && utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
