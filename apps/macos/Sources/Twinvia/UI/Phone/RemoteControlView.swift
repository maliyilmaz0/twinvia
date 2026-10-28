import SwiftUI
import TwinviaProtocol

struct RemoteControlView: View {
    @ObservedObject private var remote: RemoteControlModel
    @ObservedObject private var bridge: BridgeClient

    init(model: DashboardModel) {
        remote = model.remoteControl
        bridge = model.bridge
    }

    private var available: Bool { bridge.connected && bridge.peerCapabilities.contains("remote.screen") }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Phone screen").font(.system(.title2, design: .rounded, weight: .bold))
                    Text("A phone-approved, five-minute session. Images are loaded on demand over Bluetooth.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    remote.request(.remoteSnapshot)
                } label: {
                    Label("Refresh screen", systemImage: "arrow.clockwise")
                }.disabled(!available || remote.busy)
            }
            if remote.busy { ProgressView().controlSize(.small) }
            Text(remote.message).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button {
                    remote.request(.remoteBack)
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                Button {
                    remote.request(.remoteHome)
                } label: {
                    Label("Home", systemImage: "house")
                }
                Button {
                    remote.request(.remoteNotifications)
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }.disabled(!available || remote.busy)
            Text("Click to tap, or drag to swipe. Use Notifications to open the phone's notification panel.")
                .font(.caption).foregroundStyle(.secondary)
            if let image = remote.image, remote.imageWidth > 0, remote.imageHeight > 0 {
                let scale = min(420.0 / Double(remote.imageWidth), 700.0 / Double(remote.imageHeight))
                let width = Double(remote.imageWidth) * scale
                let height = Double(remote.imageHeight) * scale
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.secondary.opacity(0.3)))
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard available && !remote.busy else { return }
                            remote.tap(x: value.location.x / width, y: value.location.y / height)
                        }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12).onEnded { value in
                            guard available && !remote.busy else { return }
                            remote.swipe(
                                from: CGPoint(x: value.startLocation.x / width, y: value.startLocation.y / height),
                                to: CGPoint(x: value.location.x / width, y: value.location.y / height)
                            )
                        }
                    )
                    .accessibilityLabel("Phone screen. Click to tap or drag to swipe.")
                    .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(
                    "No phone image", systemImage: "iphone.gen3.radiowaves.left.and.right",
                    description: Text("Enable screen control on your phone, then select Refresh screen.")
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }
}
