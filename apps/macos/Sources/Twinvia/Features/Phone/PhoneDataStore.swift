import TwinviaProtocol
import Combine
import Foundation

@MainActor
final class PhoneDataStore: ObservableObject {
    @Published private(set) var contacts: [PhoneContact] = []
    @Published private(set) var calls: [PhoneCall] = []
    @Published private(set) var files: [PhoneFile] = []
    @Published private(set) var path = ""
    @Published private(set) var busy: Set<PhoneDataset> = []
    @Published private(set) var totals: [PhoneDataset: Int] = [:]
    @Published private(set) var next: [PhoneDataset: Int] = [:]
    @Published private(set) var errors: [PhoneDataset: String] = [:]
    @Published var contactSearch = ""
    @Published var callSearch = ""
    @Published var fileSearch = ""
    private struct Request {
        let kind: PhoneDataset
        let query: PhoneQuery
        let timeout: Task<Void, Never>
    }
    private var pending: [String: Request] = [:]
    private let available: () -> Bool
    private let send: (DeviceCommand) throws -> String

    init(available: @escaping () -> Bool, send: @escaping (DeviceCommand) throws -> String) {
        self.available = available; self.send = send
    }
    func load(_ kind: PhoneDataset, more: Bool = false, folder: String? = nil) {
        guard available() else {
            errors[kind] = "Phone disconnected or app update required."; return
        }
        if more && (next[kind] == nil || busy.contains(kind)) { return }
        // Superseded replies cannot replace a newer search/folder.
        for (id, request) in pending where request.kind == kind {
            request.timeout.cancel(); pending.removeValue(forKey: id)
        }
        if let folder, kind == .files { path = folder; fileSearch = "" }
        let search = kind == .contacts ? contactSearch : kind == .calls ? callSearch : fileSearch
        guard search.utf16.count <= 100 else {
            errors[kind] = "Search is limited to 100 UTF-16 units."; busy.remove(kind); return
        }
        let query = PhoneQuery(query: search, offset: more ? next[kind] ?? 0 : 0, path: kind == .files ? path : nil)
        if !more {
            next.removeValue(forKey: kind); totals.removeValue(forKey: kind)
            switch kind {
            case .contacts: contacts = [];
            case .calls: calls = [];
            case .files: files = []
            }
        }
        errors.removeValue(forKey: kind)
        do {
            let action: DeviceAction = kind == .contacts ? .contactsList : kind == .calls ? .callsList : .filesList
            let id = try send(DeviceCommand(action: action, browse: query))
            busy.insert(kind)
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(20)) } catch { return }
                guard let self, self.pending.removeValue(forKey: id) != nil else { return }
                self.busy.remove(kind); self.errors[kind] = "Phone did not respond. Try again."
                self.writeDiagnostics()
            }
            pending[id] = Request(kind: kind, query: query, timeout: timeout)
        } catch { busy.remove(kind); errors[kind] = error.localizedDescription }
        writeDiagnostics()
    }
    @discardableResult
    func receive(_ result: CommandResult) -> Bool {
        guard let request = pending.removeValue(forKey: result.requestId) else { return false }
        request.timeout.cancel(); busy.remove(request.kind)
        defer { writeDiagnostics() }
        guard result.success, let data = result.data, data.kind == request.kind,
            (try? data.validate()) != nil,
            request.kind != .files || data.path == request.query.path,
            data.nextOffset.map({ $0 > request.query.offset }) ?? true
        else {
            errors[request.kind] = result.success ? "No valid list received from the phone." : result.message
            return true
        }
        // Dedupe by stable provider ID when a phone record changes between pages.
        switch data.kind {
        case .contacts:
            contacts = merge(request.query.offset == 0 ? [] : contacts, data.contacts, id: \.id)
        case .calls:
            calls = merge(request.query.offset == 0 ? [] : calls, data.calls, id: \.id)
        case .files:
            files = merge(request.query.offset == 0 ? [] : files, data.files, id: \.path)
        }
        totals[data.kind] = data.total
        next[data.kind] = data.nextOffset
        return true
    }
    func disconnected() {
        pending.values.forEach { $0.timeout.cancel() }; pending = [:]
        contacts = []; calls = []; files = []; busy = []; totals = [:]; next = [:]; errors = [:]
        writeDiagnostics()
    }
    private func merge<T>(_ old: [T], _ new: [T], id: KeyPath<T, String>) -> [T] {
        let replaced = Set(new.map { $0[keyPath: id] })
        return old.filter { !replaced.contains($0[keyPath: id]) } + new
    }
    private func writeDiagnostics() {
        #if DEBUG
            // Counts/state only: no names, numbers, paths, queries or response bodies.
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.androfest.macos")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let value: [String: Any] = [
                "contactsLoaded": contacts.count, "callsLoaded": calls.count, "filesLoaded": files.count,
                "contactTotal": totals[.contacts] ?? -1, "callTotal": totals[.calls] ?? -1,
                "fileTotal": totals[.files] ?? -1,
                "busy": busy.map(\.rawValue), "failedKinds": errors.keys.map(\.rawValue),
            ]
            if let bytes = try? JSONSerialization.data(withJSONObject: value) {
                try? bytes.write(to: directory.appendingPathComponent("phone-data-status.json"), options: .atomic)
            }
        #endif
    }
}
