import Foundation

public enum DeviceAction: String, Codable, Sendable, CaseIterable {
    case callAnswerMac = "call.answer.mac"
    case callHandoffApprove = "call.handoff.approve"
    case callEnd = "call.end"
    case callAudioStart = "call.audio.start"
    case callAudioStop = "call.audio.stop"
    case contactsList = "contacts.list"
    case callsList = "calls.list"
    case filesList = "files.list"
    case filesDownload = "files.download"
    case clipboardSet = "clipboard.set"
    case ring = "device.ring"
    case stopRinging = "device.ring.stop"
    case notificationReply = "notification.reply"
    case notificationDismiss = "notification.dismiss"
    case mediaPlayPause = "media.playPause"
    case mediaNext = "media.next"
    case mediaPrevious = "media.previous"
}

public struct DeviceCommand: WirePayload {
    public static let messageType = MessageType.deviceCommand
    public let action: DeviceAction
    public let text: String?
    public let key: String?
    public let actionToken: String?
    public let browse: PhoneQuery?
    public init(
        action: DeviceAction, text: String? = nil, key: String? = nil, actionToken: String? = nil,
        browse: PhoneQuery? = nil
    ) {
        self.action = action; self.text = text; self.key = key; self.actionToken = actionToken; self.browse = browse
    }
    public func validate() throws {
        if [.contactsList, .callsList, .filesList, .filesDownload].contains(action) {
            guard text == nil, key == nil, actionToken == nil, let browse else { throw ProtocolError.invalidPayload }
            try browse.validate()
            if action == .filesDownload {
                guard let path = browse.path, !path.isEmpty, browse.query.isEmpty, browse.offset == 0 else {
                    throw ProtocolError.invalidPayload
                }
            }
            if action == .contactsList || action == .callsList {
                guard browse.path == nil else { throw ProtocolError.invalidPayload }
            }
            return
        }
        guard browse == nil else { throw ProtocolError.invalidPayload }
        switch action {
        case .callAnswerMac, .callHandoffApprove, .callEnd, .callAudioStart, .callAudioStop:
            guard text == nil, key == nil, let actionToken, UUID(uuidString: actionToken) != nil else {
                throw ProtocolError.invalidPayload
            }
        case .clipboardSet:
            guard let text, !text.isEmpty, text.utf16.count <= 16_384, key == nil, actionToken == nil else {
                throw ProtocolError.invalidPayload
            }
        case .notificationReply, .notificationDismiss:
            guard let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, key.utf16.count <= 4096,
                let actionToken, UUID(uuidString: actionToken) != nil
            else { throw ProtocolError.invalidPayload }
            if action == .notificationReply {
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf16.count <= 4096
                else { throw ProtocolError.invalidPayload }
            } else if text != nil {
                throw ProtocolError.invalidPayload
            }
        default:
            guard text == nil, key == nil, actionToken == nil else { throw ProtocolError.invalidPayload }
        }
    }
}

public struct CommandResult: WirePayload {
    public static let messageType = MessageType.commandResult
    public let requestId: String
    public let success: Bool
    public let message: String
    public let data: PhonePage?
    public init(requestId: String, success: Bool, message: String, data: PhonePage? = nil) {
        self.requestId = requestId; self.success = success; self.message = message; self.data = data
    }
    public func validate() throws {
        guard UUID(uuidString: requestId) != nil, !message.isEmpty, message.utf16.count <= 256, success || data == nil
        else { throw ProtocolError.invalidPayload }
        try data?.validate()
    }
}

public struct DeviceStatus: WirePayload, Equatable {
    public static let messageType = MessageType.deviceStatus
    public let batteryPercent: Int?
    public let charging: Bool
    public let locked: Bool
    public let mediaTitle: String?
    public let mediaArtist: String?
    public let mediaPlaying: Bool
    public let ringing: Bool
    public let call: PhoneCallState?
    public init(
        batteryPercent: Int?, charging: Bool, locked: Bool, mediaTitle: String? = nil,
        mediaArtist: String? = nil, mediaPlaying: Bool = false, ringing: Bool = false, call: PhoneCallState? = nil
    ) {
        self.batteryPercent = batteryPercent; self.charging = charging; self.locked = locked
        self.mediaTitle = mediaTitle; self.mediaArtist = mediaArtist; self.mediaPlaying = mediaPlaying;
        self.ringing = ringing; self.call = call
    }
    public func validate() throws {
        try call?.validate()
        guard batteryPercent.map({ (0...100).contains($0) }) ?? true,
            (mediaTitle?.utf16.count ?? 0) <= 512, (mediaArtist?.utf16.count ?? 0) <= 512
        else { throw ProtocolError.invalidPayload }
    }
}

public struct SharedText: WirePayload {
    public static let messageType = MessageType.sharedText
    public let text: String
    public let isClipboard: Bool?
    public init(text: String, isClipboard: Bool? = nil) { self.text = text; self.isClipboard = isClipboard }
    public func validate() throws {
        guard !text.isEmpty, text.utf16.count <= 16_384 else { throw ProtocolError.invalidPayload }
    }
}

public struct PhoneCallState: Codable, Sendable, Equatable {
    public let state: String
    public let token: String?
    public let approval: String?
    public init(state: String, token: String? = nil, approval: String? = nil) {
        self.state = state; self.token = token; self.approval = approval
    }
    public func validate() throws {
        guard ["idle", "ringing", "active"].contains(state) else { throw ProtocolError.invalidPayload }
        if state == "idle" {
            guard token == nil, approval == nil else { throw ProtocolError.invalidPayload }
        } else {
            guard let token, UUID(uuidString: token) != nil,
                approval.map({ UUID(uuidString: $0) != nil }) ?? true
            else { throw ProtocolError.invalidPayload }
        }
    }
}
