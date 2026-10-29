import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject private var bridge: BridgeClient
    @ObservedObject private var transfers: FileTransferController
    @State private var showFilePicker = false
    @State private var dropTargeted = false
    @Environment(\.scenePhase) private var scenePhase
    private let accent = FestTheme.violet

    init(model: DashboardModel) {
        self.model = model
        self.bridge = model.bridge
        self.transfers = model.transfers
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 20) {
                    ConnectionOrbit(connected: bridge.connected)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Control center").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(bridge.peerName ?? "Your phone and Mac, together.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(
                        bridge.connected ? "Connected" : "Waiting",
                        systemImage: bridge.connected ? "checkmark.shield.fill" : "clock"
                    )
                    .foregroundStyle(bridge.connected ? FestTheme.lime : FestTheme.violet)
                }
                if bridge.requiresKeychainAccess {
                    FestCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Your pairing is preserved", systemImage: "key.fill").font(.headline)
                            Text("System permission is required to unlock the saved phone key.").font(.callout)
                            Button("Allow pairing key access") { bridge.readSavedTrust() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                Picker("Section", selection: $model.dashboardSection) {
                    Text("General").tag(0)
                    Text("Files").tag(1)
                    Text("Calls").tag(2)
                    Text("Notifications").tag(3)
                    Text("Contacts").tag(4)
                    Text("History").tag(5)
                    Text("Screen").tag(6)
                }.pickerStyle(.segmented)

                if model.dashboardSection == 0 {
                    GroupBox("Phone connection") {
                        HStack(alignment: .top, spacing: 24) {
                            if let invitation = bridge.invitation,
                                let link = try? invitation.link(), let image = PairingQRCode.image(for: link)
                            {
                                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                                    .frame(width: 240, height: 240).padding(16).background(.white)
                            }
                            VStack(alignment: .leading, spacing: 12) {
                                Text(bridge.status).font(.headline)
                                if bridge.peerName == nil {
                                    Text("Open Twinvia on your phone and tap 'Scan Mac QR code'.")
                                    Text(
                                        "The QR code expires in five minutes. Keep Bluetooth enabled and devices nearby; no shared network or internet is needed."
                                    )
                                    .font(.callout).foregroundStyle(.secondary)
                                }
                                if bridge.peerName == nil {
                                    Button("Generate new QR code", action: bridge.renewInvitation)
                                }
                                if bridge.peerName != nil {
                                    Button("Remove pairing on this Mac", action: model.forgetPhone)
                                }
                                Divider()
                                Text(bridge.transportStatus).font(.callout)
                                if !bridge.connected {
                                    Button("Retry connection", action: bridge.connectPeer)
                                }
                            }
                            Spacer()
                        }.padding(12)
                    }

                    GroupBox {
                        HStack(spacing: 18) {
                            Image(systemName: "desktopcomputer").font(.system(size: 36)).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.deviceName).font(.title3.bold())
                                Text(ProcessInfo.processInfo.operatingSystemVersionString).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Mac ready").foregroundStyle(accent)
                        }.padding(14)
                    }

                }
                if model.dashboardSection == 4 { PhoneBrowserView(kind: .contacts, model: model) }
                if model.dashboardSection == 5 { PhoneBrowserView(kind: .calls, model: model) }
                if model.dashboardSection == 6 { RemoteControlView(model: model) }
                if model.dashboardSection == 1 {
                    PhoneBrowserView(kind: .files, model: model)
                    Divider().padding(.vertical, 8)
                    GroupBox("Send a file from Mac to phone") {
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(spacing: 10) {
                                Image(systemName: "arrow.up.document").font(.system(size: 30)).foregroundStyle(accent)
                                Text("Drop your files here").font(.headline)
                                Text("Send a file to your phone or accept an incoming file. Limit: 2 GiB.")
                                    .foregroundStyle(.secondary)
                                Button("Choose file") { showFilePicker = true }
                                    .disabled(model.isInspecting)
                            }
                            .frame(maxWidth: .infinity).padding(28)
                            .background(dropTargeted ? accent.opacity(0.12) : Color.primary.opacity(0.025))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .dropDestination(for: URL.self) { urls, _ in
                                guard !model.isInspecting else { return false }
                                model.selectFiles(urls)
                                return true
                            } isTargeted: {
                                dropTargeted = $0
                            }
                            if model.isInspecting { ProgressView("Preparing files…") }
                            ForEach(model.files) { file in
                                HStack {
                                    Image(systemName: "doc")
                                    Text(file.offer.fileName).lineLimit(1)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: file.offer.size, countStyle: .file))
                                        .foregroundStyle(.secondary)
                                    Button("Send to phone") { transfers.sendFile(file) }
                                        .disabled(
                                            !bridge.connected || !bridge.peerCapabilities.contains("files.receive")
                                                || transfers.status.busy)
                                }
                            }
                            if !model.files.isEmpty {
                                Button("Clear selection", action: model.clearFiles).disabled(model.isInspecting)
                            }
                            if !transfers.status.message.isEmpty {
                                Text(transfers.status.fileName).font(.headline)
                                Text(transfers.status.message)
                                if transfers.status.busy {
                                    ProgressView(
                                        value: Double(transfers.status.bytes),
                                        total: Double(max(transfers.status.total, 1)))
                                    Text(
                                        "\(ByteCountFormatter.string(fromByteCount: transfers.status.bytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: transfers.status.total, countStyle: .file))"
                                    ).font(.caption)
                                    Button("Cancel transfer") { transfers.cancel() }
                                }
                                if let received = transfers.status.receivedURL {
                                    Button("Show in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([received])
                                    }
                                }
                            }
                        }.padding(12)
                    }

                }
                if model.dashboardSection == 0 {
                    DailyFeaturesView(controls: model.controls, bridge: bridge, clipboard: model.clipboard)
                    UpdateSettingsView()
                }
                if model.dashboardSection == 2 {
                    CallsView(model: model, calls: model.calls)
                }

                if model.dashboardSection == 3 {
                    GroupBox("Notifications") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(model.notificationStatus)
                                Spacer()
                                Button("Allow") { Task { await model.requestNotificationAccess() } }
                                Button("System settings") {
                                    if let url = URL(
                                        string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
                                    {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                            }
                            Text("Notifications received from phone: \(bridge.receivedCount)").font(.callout)
                            ForEach(model.recentNotifications, id: \.key) { notification in
                                HStack(alignment: .top, spacing: 10) {
                                    if let encoded = notification.appIconPng,
                                        let data = Data(base64Encoded: encoded), let image = NSImage(data: data)
                                    {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 36)
                                            .accessibilityLabel("\(notification.appName) simgesi")
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(notification.appName).font(.caption).foregroundStyle(.secondary)
                                        Text(notification.title ?? "Notification").font(.headline)
                                        if let text = notification.text { Text(text).lineLimit(4) }
                                        NotificationActionsView(
                                            notification: notification, controls: model.controls,
                                            available: bridge.connected
                                                && bridge.peerCapabilities.contains("notifications.actions"))
                                    }
                                    Spacer()
                                    Button("Mute") { model.muteApplication(notification) }
                                        .help("\(notification.appName) hide notifications on this Mac")
                                }
                            }
                            if !model.mutedApplications.isEmpty {
                                Divider()
                                Text("Muted apps").font(.caption).foregroundStyle(.secondary)
                                ForEach(model.mutedApplications.keys.sorted(), id: \.self) { packageName in
                                    HStack {
                                        Text(model.mutedApplications[packageName] ?? packageName)
                                        Spacer()
                                        Button("Fetch again") { model.unmuteApplication(packageName) }
                                    }
                                }
                            }
                        }.padding(12)
                    }
                }
                HStack {
                    Button("Validate protocol", action: model.checkProtocol)
                    if let notice = model.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
                }
            }.padding(30)
        }
        .alert("Incoming file", isPresented: Binding(get: { transfers.incomingOffer != nil }, set: { _ in })) {
            Button("Accept") { transfers.accept() }
            Button("Decline", role: .cancel) { transfers.cancel(reason: "File declined.") }
        } message: {
            if let offer = transfers.incomingOffer {
                Text(
                    "\(offer.fileName) · \(ByteCountFormatter.string(fromByteCount: offer.size, countStyle: .file))\nWill be saved in Downloads/Twinvia."
                )
            }
        }
        .frame(minWidth: 700, minHeight: 580)
        .background(FestTheme.background)
        .preferredColorScheme(.dark)
        .groupBoxStyle(FestGroupStyle())
        .tint(accent)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item], allowsMultipleSelection: true) {
            switch $0 {
            case .success(let urls): model.selectFiles(urls)
            case .failure(let error): model.showError(error)
            }
        }
        .task { await model.refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refreshNotificationStatus() } }
        }
    }
}
