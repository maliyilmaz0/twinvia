import AndrofestProtocol
import Foundation

/// Typed routing of application envelopes. Binary audio/file frames are handled by their codecs.
enum BridgeEvent {
    case notification(WireEnvelope<NotificationPosted>)
    case notificationRemoved(String)
    case file(FileControl)
    case deviceStatus(DeviceStatus)
    case sharedText(SharedText)
    case commandResult(CommandResult)

    static func decode(_ data: Data) throws -> BridgeEvent {
        let header = try JSONDecoder().decode(Header.self, from: data)
        switch header.type {
        case .notificationPosted: return .notification(try WireCodec.decode(NotificationPosted.self, from: data))
        case .notificationRemoved:
            return .notificationRemoved(try WireCodec.decode(NotificationRemoved.self, from: data).payload.key)
        case .fileOffer: return .file(.offer(try WireCodec.decode(FileOffer.self, from: data).payload))
        case .fileAccept: return .file(.accept(try WireCodec.decode(FileAccept.self, from: data).payload))
        case .fileComplete: return .file(.complete(try WireCodec.decode(FileComplete.self, from: data).payload))
        case .fileCancel: return .file(.cancel(try WireCodec.decode(FileCancel.self, from: data).payload))
        case .deviceStatus: return .deviceStatus(try WireCodec.decode(DeviceStatus.self, from: data).payload)
        case .sharedText: return .sharedText(try WireCodec.decode(SharedText.self, from: data).payload)
        case .commandResult: return .commandResult(try WireCodec.decode(CommandResult.self, from: data).payload)
        default: throw ProtocolError.invalidPayload
        }
    }

    struct Header: Decodable {
        let id: String
        let type: MessageType
        let sourceDeviceId: String
    }
}
