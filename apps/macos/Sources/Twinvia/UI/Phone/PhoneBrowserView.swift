import TwinviaProtocol
import AppKit
import SwiftUI

struct PhoneBrowserView: View {
    let kind: PhoneDataset
    @ObservedObject var model: DashboardModel
    @ObservedObject private var store: PhoneDataStore
    @ObservedObject private var bridge: BridgeClient
    @ObservedObject private var transfers: FileTransferController
    @ObservedObject private var controls: DeviceControls

    init(kind: PhoneDataset, model: DashboardModel) {
        self.kind = kind; self.model = model; store = model.phoneData; bridge = model.bridge;
        transfers = model.transfers; controls = model.controls
    }
    private var title: String { kind == .contacts ? "Contacts" : kind == .calls ? "Call history" : "Phone files" }
    private var search: Binding<String> {
        switch kind {
        case .contacts: $store.contactSearch;
        case .calls: $store.callSearch;
        case .files: $store.fileSearch
        }
    }
    private var canBrowse: Bool { bridge.connected && bridge.peerCapabilities.contains("phone.browse") }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.title2, design: .rounded, weight: .bold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.load(kind)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!canBrowse || store.busy.contains(kind))
            }
            HStack {
                TextField(kind == .files ? "Search this folder" : "Search name or number", text: search)
                    .textFieldStyle(.roundedBorder).onSubmit { store.load(kind) }
                Button("Call") { store.load(kind) }.disabled(!canBrowse)
            }
            if kind == .files { folderNavigation }
            if !canBrowse {
                empty(
                    "Waiting for phone connection",
                    detail: "Refresh these lists once your paired phone connects.", icon: "iphone.slash")
            } else if let error = store.errors[kind] {
                empty("Could not load the list", detail: error, icon: "exclamationmark.circle")
            } else if count == 0 && !store.busy.contains(kind) {
                empty(
                    "No records yet",
                    detail: "Grant permissions and press Refresh. Clear the search and try again if needed.",
                    icon: "tray")
            }
            if store.busy.contains(kind) { ProgressView("Loading from phone…").controlSize(.small) }
            LazyVStack(spacing: 8) {
                switch kind {
                case .contacts:
                    ForEach(store.contacts) { contact in
                        FestCard {
                            HStack(spacing: 14) {
                                avatar(contact.name.isEmpty ? contact.number : contact.name)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(contact.name.isEmpty ? "Unnamed contact" : contact.name).font(.headline)
                                    Text(contact.number).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                prepareCall(contact.number)
                            }
                        }
                    }
                case .calls:
                    ForEach(store.calls) { call in
                        FestCard {
                            HStack(spacing: 14) {
                                Image(
                                    systemName: call.type == 2
                                        ? "phone.arrow.up.right"
                                        : call.type == 3 ? "phone.badge.waveform" : "phone.arrow.down.left"
                                )
                                .font(.title2).foregroundStyle(call.type == 3 ? .orange : FestTheme.violet)
                                .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(
                                        call.name.isEmpty
                                            ? (call.number.isEmpty ? "Private number" : call.number) : call.name
                                    ).font(.headline)
                                    HStack {
                                        Text(callType(call.type))
                                        if !call.number.isEmpty && !call.name.isEmpty { Text("· \(call.number)") }
                                    }.foregroundStyle(.secondary).textSelection(.enabled)
                                    Text(
                                        "\(Date(timeIntervalSince1970: Double(call.timestamp) / 1000).formatted(date: .abbreviated, time: .shortened)) · \(duration(call.duration))"
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                prepareCall(call.number)
                            }
                        }
                    }
                case .files:
                    ForEach(store.files) { file in
                        FestCard {
                            HStack(spacing: 14) {
                                Image(systemName: file.directory ? "folder.fill" : "doc")
                                    .font(.title2).foregroundStyle(file.directory ? FestTheme.violet : .secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    if file.directory {
                                        Button(file.name) { store.load(.files, folder: file.path) }.buttonStyle(.link)
                                            .font(.headline)
                                    } else {
                                        Text(file.name).font(.headline).textSelection(.enabled)
                                    }
                                    Text(
                                        file.directory
                                            ? "Folder"
                                            : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
                                    )
                                    .font(.caption).foregroundStyle(.secondary)
                                    if file.modified > 0 {
                                        Text(
                                            Date(timeIntervalSince1970: Double(file.modified) / 1000),
                                            format: .dateTime.day().month().year()
                                        )
                                        .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if !file.directory {
                                    Button("Download to Mac") {
                                        controls.perform(
                                            DeviceCommand(action: .filesDownload, browse: PhoneQuery(path: file.path)))
                                    }
                                    .disabled(
                                        !canBrowse || controls.busy || transfers.status.busy
                                            || file.size > FileChunk.maxFileBytes)
                                }
                            }
                        }
                    }
                }
            }
            if store.next[kind] != nil {
                Button("Show more") { store.load(kind, more: true) }
                    .disabled(store.busy.contains(kind) || !canBrowse).frame(maxWidth: .infinity)
            }
            if kind == .files && !controls.message.isEmpty {
                Text(controls.message).font(.callout).foregroundStyle(.secondary)
            }
            if kind == .files && !transfers.status.message.isEmpty {
                Text(transfers.status.message).font(.callout).foregroundStyle(.secondary)
                if transfers.status.busy {
                    ProgressView(value: Double(transfers.status.bytes), total: Double(max(1, transfers.status.total)))
                }
                if let url = transfers.status.receivedURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
        }
        .task(id: bridge.connected) {
            if canBrowse && store.totals[kind] == nil && !store.busy.contains(kind) { store.load(kind) }
        }
    }
    private var count: Int {
        kind == .contacts ? store.contacts.count : kind == .calls ? store.calls.count : store.files.count
    }
    private var subtitle: String {
        let total = store.totals[kind].map { "\(count) / \($0) records" } ?? "Live encrypted access to your phone"
        return kind == .files ? "Internal storage · \(total)" : total
    }
    private var folderNavigation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    store.load(.files, folder: "")
                } label: {
                    Label("Internal storage", systemImage: "internaldrive")
                }
                Button("Parent folder") {
                    let parts = store.path.split(separator: "/").dropLast()
                    store.load(.files, folder: parts.joined(separator: "/"))
                }.disabled(store.path.isEmpty)
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(["Download", "DCIM", "Pictures", "Documents", "Music"], id: \.self) { folder in
                        Button(folder) { store.load(.files, folder: folder) }
                    }
                }
            }
            Text(store.path.isEmpty ? "/" : "/\(store.path)").font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Text(
                "Downloads are saved in Downloads/Twinvia on Mac. Android/data and private application data are inaccessible."
            )
            .font(.caption).foregroundStyle(.secondary)
        }.disabled(!canBrowse)
    }
    private func avatar(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased()).font(.title3.bold()).foregroundStyle(FestTheme.violet)
            .frame(width: 42, height: 42).background(FestTheme.violet.opacity(0.12), in: Circle()).accessibilityHidden(
                true)
    }
    private func prepareCall(_ number: String) -> some View {
        Button {
            model.dialNumber = number; model.dashboardSection = 2
        } label: {
            Label("Call screen", systemImage: "phone")
        }
        .disabled(CallNumber.normalize(number) == nil)
    }
    private func empty(_ title: String, detail: String, icon: String) -> some View {
        FestCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private func callType(_ type: Int) -> String {
        switch type {
        case 1: "Incoming";
        case 2: "Outgoing";
        case 3: "Missed";
        case 4: "Voicemail";
        case 5: "Declined";
        case 6: "Blocked";
        case 7: "Answered on another device";
        default: "Other"
        }
    }
    private func duration(_ seconds: Int64) -> String {
        seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) sec" : "\(seconds) sec"
    }
}
