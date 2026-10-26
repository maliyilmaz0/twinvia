import Foundation

public enum PhoneDataset: String, Codable, Sendable, Hashable { case contacts, calls, files }

public struct PhoneQuery: Codable, Sendable {
    public let query: String
    public let offset: Int
    public let path: String?
    public init(query: String = "", offset: Int = 0, path: String? = nil) {
        self.query = query; self.offset = offset; self.path = path
    }
    public func validate() throws {
        guard query.utf16.count <= 100, (0...1_000_000).contains(offset), path.map(validPhonePath) ?? true else {
            throw ProtocolError.invalidPayload
        }
    }
}

public func validPhonePath(_ path: String) -> Bool {
    path.utf16.count <= 1024 && !path.hasPrefix("/") && !path.contains("\0")
        && !path.components(separatedBy: "/").contains(where: { $0 == "." || $0 == ".." })
}

public struct PhoneContact: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let number: String
    public init(id: String, name: String, number: String) { self.id = id; self.name = name; self.number = number }
}
public struct PhoneCall: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let number: String
    public let timestamp: Int64
    public let duration: Int64
    public let type: Int
    public init(id: String, name: String, number: String, timestamp: Int64, duration: Int64, type: Int) {
        self.id = id; self.name = name; self.number = number; self.timestamp = timestamp; self.duration = duration;
        self.type = type
    }
}
public struct PhoneFile: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let directory: Bool
    public let size: Int64
    public let modified: Int64
    public init(path: String, name: String, directory: Bool, size: Int64, modified: Int64) {
        self.path = path; self.name = name; self.directory = directory; self.size = size; self.modified = modified
    }
}

public struct PhonePage: Codable, Sendable {
    public let kind: PhoneDataset
    public let contacts: [PhoneContact]
    public let calls: [PhoneCall]
    public let files: [PhoneFile]
    public let nextOffset: Int?
    public let total: Int
    public let path: String?
    public init(
        kind: PhoneDataset, contacts: [PhoneContact] = [], calls: [PhoneCall] = [], files: [PhoneFile] = [],
        nextOffset: Int? = nil, total: Int = 0, path: String? = nil
    ) {
        self.kind = kind; self.contacts = contacts; self.calls = calls; self.files = files
        self.nextOffset = nextOffset; self.total = total; self.path = path
    }
    public func validate() throws {
        guard (0...1_000_000).contains(total), nextOffset.map({ (1...1_000_000).contains($0) }) ?? true,
            contacts.count <= 50, calls.count <= 50, files.count <= 50,
            kind == .contacts || contacts.isEmpty, kind == .calls || calls.isEmpty,
            kind == .files || (files.isEmpty && path == nil), path.map(validPhonePath) ?? true,
            Set(contacts.map(\.id)).count == contacts.count, Set(calls.map(\.id)).count == calls.count,
            Set(files.map(\.path)).count == files.count
        else { throw ProtocolError.invalidPayload }
        for item in contacts {
            guard (1...128).contains(item.id.utf16.count), item.name.utf16.count <= 256, item.number.utf16.count <= 128
            else { throw ProtocolError.invalidPayload }
        }
        for item in calls {
            guard (1...128).contains(item.id.utf16.count), item.name.utf16.count <= 256, item.number.utf16.count <= 128,
                (1...9_007_199_254_740_991).contains(item.timestamp),
                (0...9_007_199_254_740_991).contains(item.duration),
                (0...20).contains(item.type)
            else { throw ProtocolError.invalidPayload }
        }
        for item in files {
            guard !item.path.isEmpty, validPhonePath(item.path), !item.name.isEmpty, item.name.utf16.count <= 256,
                (0...9_007_199_254_740_991).contains(item.size), (0...9_007_199_254_740_991).contains(item.modified)
            else { throw ProtocolError.invalidPayload }
        }
    }
}
