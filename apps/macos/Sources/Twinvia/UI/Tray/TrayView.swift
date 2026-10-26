import TwinviaProtocol
import AppKit
import SwiftUI

enum FestTheme {
    static let violet = Color(red: 0.74, green: 0.68, blue: 1)
    static let lime = Color(red: 0.79, green: 0.96, blue: 0.60)
    static let background = Color(red: 0.063, green: 0.071, blue: 0.133)
    static let surface = Color(red: 0.11, green: 0.125, blue: 0.21)
}

struct ConnectionOrbit: View {
    let connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || !visible)) { timeline in
            let angle =
                reduceMotion
                ? 35 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) * 30
            ZStack {
                Circle().fill(FestTheme.violet.opacity(0.10))
                Circle().stroke(FestTheme.violet.opacity(0.18), lineWidth: 1).padding(7)
                Circle().trim(from: 0, to: connected ? 0.72 : 0.28)
                    .stroke(
                        AngularGradient(
                            colors: [
                                FestTheme.violet.opacity(0.1), FestTheme.violet,
                                connected ? FestTheme.lime : FestTheme.violet,
                            ], center: .center),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .padding(7).rotationEffect(.degrees(angle))
                Image(systemName: connected ? "iphone.radiowaves.left.and.right" : "iphone")
                    .font(.system(size: 28, weight: .medium)).foregroundStyle(.white)
            }
        }
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}

struct FestCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(FestTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

struct TrayView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject private var bridge: BridgeClient
    @ObservedObject private var clipboard: AutomaticClipboard
    @ObservedObject private var controls: DeviceControls
    @ObservedObject private var calls: HandsFreeController
    @ObservedObject private var transfers: FileTransferController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab = 0

    init(model: DashboardModel) {
        self.model = model; bridge = model.bridge; clipboard = model.clipboard
        controls = model.controls; calls = model.calls; transfers = model.transfers
    }

    private var canControl: Bool {
        bridge.connected && bridge.peerCapabilities.contains("device.commands") && !controls.busy
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Twinvia", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text("TWO DEVICES. ONE FLOW.").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.6).foregroundStyle(FestTheme.violet)
            }.padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
                    connectionCard
                    if let offer = transfers.incomingOffer {
                        FestCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Incoming file", systemImage: "tray.and.arrow.down").font(.headline)
                                Text(offer.fileName).font(.callout)
                                Text("Will be saved in Downloads/Twinvia.").font(.caption).foregroundStyle(
                                    .secondary)
                                HStack {
                                    Button("Accept") { transfers.accept() }.buttonStyle(.borderedProminent)
                                    Button("Decline") { transfers.cancel(reason: "File declined.") }
                                }
                            }
                        }
                    }
                    Picker("Section", selection: $tab) {
                        Text("Controls").tag(0)
                        Text("Notifications").tag(1)
                        Text("Calls").tag(2)
                    }.pickerStyle(.segmented)
                    Group {
                        switch tab {
                        case 1: notifications
                        case 2: CallsView(model: model, calls: calls)
                        default: quickControls
                        }
                    }.transition(.opacity)
                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }
            Divider().overlay(.white.opacity(0.08))
            HStack {
                Button(action: showDashboard) { Label("Control center", systemImage: "slider.horizontal.3") }
                    .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power").frame(width: 28, height: 28)
                }.accessibilityLabel("Quit Twinvia").help("Quit Twinvia")
            }.buttonStyle(.borderless).padding(.horizontal, 22).padding(.vertical, 12)
        }
        .frame(width: 400, height: 660)
        .background {
            ZStack(alignment: .topTrailing) {
                FestTheme.background
                Ellipse().fill(FestTheme.violet.opacity(0.12)).frame(width: 290, height: 220)
                    .blur(radius: 55).offset(x: 90, y: -100)
            }
        }
        .preferredColorScheme(.dark).tint(FestTheme.violet)
        .groupBoxStyle(FestGroupStyle())
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: tab)
        .task { await model.refreshNotificationStatus() }

    }

    private var connectionCard: some View {
        FestCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    ConnectionOrbit(connected: bridge.connected)
                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            bridge.connected ? "CONNECTED" : "WAITING",
                            systemImage: bridge.connected ? "checkmark.circle.fill" : "clock"
                        )
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                        .foregroundStyle(bridge.connected ? FestTheme.lime : FestTheme.violet)
                        Text(bridge.peerName ?? "Connect your phone")
                            .font(.system(.title2, design: .rounded, weight: .bold)).lineLimit(2)
                        Text(bridge.connected ? "Nearby. Secure. Together." : bridge.status)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if bridge.connected {
                    HStack {
                        Label("Bluetooth LE", systemImage: "wave.3.right")
                        Spacer()
                        Label("Encrypted", systemImage: "lock.shield")
                    }.font(.caption).foregroundStyle(.secondary)
                    if let phone = controls.phone {
                        HStack {
                            Label(
                                phone.batteryPercent.map { "%\($0)" } ?? "Battery unknown",
                                systemImage: phone.charging ? "battery.100.bolt" : "battery.50")
                            Spacer()
                            Text(phone.locked ? "Phone locked" : "Phone unlocked")
                        }.font(.callout).foregroundStyle(FestTheme.lime)
                    }
                } else {
                    Text(bridge.transportStatus).font(.caption).foregroundStyle(.secondary)
                    Button(action: showDashboard) {
                        Label(
                            bridge.peerName == nil ? "Pair using QR code" : "Manage connection", systemImage: "qrcode"
                        )
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.buttonStyle(.borderedProminent).foregroundStyle(FestTheme.background)
                }
            }
        }
    }

    private var quickControls: some View {
        VStack(spacing: 12) {
            FestCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Universal clipboard", systemImage: "document.on.clipboard")
                            .font(.headline)
                        Spacer()
                        Toggle(
                            "Automatic clipboard sync",
                            isOn: Binding(get: { clipboard.enabled }, set: { clipboard.setEnabled($0) })
                        )
                        .labelsHidden().toggleStyle(.switch)
                    }
                    Text(clipboard.status).font(.callout).foregroundStyle(.secondary)
                    Text("Copy on one. Paste on the other.").font(.caption).foregroundStyle(FestTheme.violet)
                }
            }
            HStack(spacing: 12) {
                Button {
                    controls.perform(DeviceCommand(action: .ring))
                } label: {
                    quickTile("Find phone", icon: "bell.badge.waveform")
                }.disabled(!canControl).opacity(canControl ? 1 : 0.45)
                Button {
                    model.dashboardSection = 1; showDashboard()
                } label: {
                    quickTile("Send file", icon: "arrow.up.doc")
                }
            }.buttonStyle(.plain)
            HStack(spacing: 12) {
                Button {
                    model.dashboardSection = 4; showDashboard()
                } label: {
                    quickTile("Contacts", icon: "person.crop.rectangle.stack")
                }
                Button {
                    model.dashboardSection = 5; showDashboard()
                } label: {
                    quickTile("Call history", icon: "clock.arrow.circlepath")
                }
            }.buttonStyle(.plain)
            Button("Stop phone ringer") { controls.perform(DeviceCommand(action: .stopRinging)) }
                .buttonStyle(.borderless).disabled(!canControl)
            if !controls.message.isEmpty { Text(controls.message).font(.caption).foregroundStyle(.secondary) }
            if controls.phone?.mediaTitle != nil { mediaCard }
            if transfers.status.busy {
                FestCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(transfers.status.fileName, systemImage: "arrow.up.arrow.down").lineLimit(1)
                        ProgressView(
                            value: Double(transfers.status.bytes), total: Double(max(transfers.status.total, 1)))
                        Text(transfers.status.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func quickTile(_ title: String, icon: String) -> some View {
        FestCard {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(FestTheme.violet).accessibilityHidden(true)
                Text(title).font(.callout.weight(.semibold))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var mediaCard: some View {
        FestCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controls.phone?.mediaTitle ?? "").font(.headline).lineLimit(1)
                    Text(controls.phone?.mediaArtist ?? "Ringing on phone").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    controls.perform(DeviceCommand(action: .mediaPlayPause))
                } label: {
                    Image(systemName: controls.phone?.mediaPlaying == true ? "pause.fill" : "play.fill")
                        .frame(width: 32, height: 32)
                }.disabled(!canControl).accessibilityLabel("Play or pause media")
            }
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT NOTIFICATIONS").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.recentNotifications.count)").font(.caption.monospacedDigit()).foregroundStyle(
                    FestTheme.violet)
            }
            if model.recentNotifications.isEmpty {
                FestCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Quiet for now", systemImage: "bell.slash").font(.headline)
                        Text("Phone notifications appear here and in macOS Notification Center.")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Manage notification permissions", action: showDashboard)
                    }
                }
            }
            ForEach(model.recentNotifications.prefix(8), id: \.key) { notification in
                FestCard {
                    HStack(alignment: .top, spacing: 12) {
                        if let encoded = notification.appIconPng, let data = Data(base64Encoded: encoded),
                            let icon = NSImage(data: data)
                        {
                            Image(nsImage: icon).resizable().scaledToFit().frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(notification.appName).font(.caption).foregroundStyle(FestTheme.violet)
                            Text(notification.title ?? "Notification").font(.headline)
                            if let text = notification.text {
                                Text(text).font(.callout).lineLimit(3).foregroundStyle(.secondary)
                            }
                            NotificationActionsView(
                                notification: notification, controls: controls,
                                available: bridge.connected && bridge.peerCapabilities.contains("notifications.actions")
                            )
                        }
                    }
                }
            }
        }
    }

    private func showDashboard() {
        DashboardWindow.show(model: model)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct FestGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        FestCard {
            VStack(alignment: .leading, spacing: 12) {
                configuration.label.font(.headline).foregroundStyle(FestTheme.violet)
                configuration.content
            }
        }
    }
}
