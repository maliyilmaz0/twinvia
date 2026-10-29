import SwiftUI

struct RemoteControlView: View {
    private let model: DashboardModel
    @ObservedObject private var bridge: BridgeClient
    init(model: DashboardModel) { self.model = model; bridge = model.bridge }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Phone mirror", systemImage: "iphone.radiowaves.left.and.right")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Open a dedicated, resizable phone window with tap, swipe, navigation and optional keyboard controls.")
                .foregroundStyle(.secondary)
            Button("Open phone mirror…") { MirrorWindow.show(model: model) }
                .buttonStyle(.borderedProminent)
            Text(
                "Approve screen viewing on the phone first. Touch and keyboard input require separate control approval."
            )
            .font(.callout)
            Text(
                "Choose Detail in the mirror window for sharper text. The optional faster Bluetooth lane is experimental; BLE remains available for normal controls."
            )
            .font(.caption).foregroundStyle(.secondary)
            Label(
                bridge.connected ? "Phone connected" : "Connect your phone to begin",
                systemImage: bridge.connected ? "checkmark.shield" : "link")
        }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
    }
}
