import TwinviaProtocol
import SwiftUI

struct DailyFeaturesView: View {
    @ObservedObject var controls: DeviceControls
    @ObservedObject var bridge: BridgeClient
    @ObservedObject var clipboard: AutomaticClipboard
    private var enabled: Bool {
        bridge.connected && bridge.peerCapabilities.contains("device.commands") && !controls.busy
    }
    var body: some View {
        GroupBox("Phone and sharing") {
            VStack(alignment: .leading, spacing: 12) {
                if let phone = controls.phone {
                    HStack {
                        Label(
                            phone.batteryPercent.map { "%\($0)" } ?? "Battery unknown",
                            systemImage: phone.charging ? "battery.100.bolt" : "battery.50")
                        Text(phone.charging ? "Charging" : "On battery")
                        Spacer()
                        Image(systemName: phone.locked ? "lock" : "lock.open")
                    }
                    if let title = phone.mediaTitle {
                        Text(title).font(.headline)
                        if let artist = phone.mediaArtist { Text(artist).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Button("Ring phone") { controls.perform(DeviceCommand(action: .ring)) }.disabled(!enabled)
                    Button("Stop audio") { controls.perform(DeviceCommand(action: .stopRinging)) }.disabled(!enabled)
                    Spacer()
                    Button {
                        controls.perform(DeviceCommand(action: .mediaPrevious))
                    } label: {
                        Image(systemName: "backward.end")
                    }.help("Previous track").disabled(!enabled)
                    Button {
                        controls.perform(DeviceCommand(action: .mediaPlayPause))
                    } label: {
                        Image(systemName: controls.phone?.mediaPlaying == true ? "pause" : "play")
                    }.help("Play / pause").disabled(!enabled)
                    Button {
                        controls.perform(DeviceCommand(action: .mediaNext))
                    } label: {
                        Image(systemName: "forward.end")
                    }.help("Next track").disabled(!enabled)
                }
                Divider()
                Toggle(
                    "Automatic clipboard sync",
                    isOn: Binding(get: { clipboard.enabled }, set: { clipboard.setEnabled($0) }))
                Text(clipboard.status).font(.callout).foregroundStyle(.secondary)
                Text("Text and links copied on one device automatically reach the other clipboard.")
                    .font(.caption).foregroundStyle(.secondary)
                if !controls.message.isEmpty { Text(controls.message).font(.callout).foregroundStyle(.secondary) }
            }.padding(12)
        }
    }
}

struct CallsView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var calls: HandsFreeController
    @State private var proposedNumber: String?
    var body: some View {
        GroupBox("Calls") {
            VStack(alignment: .leading, spacing: 12) {
                Text(calls.status).font(.headline)
                Text(
                    model.phoneCall.map {
                        $0.state == "ringing"
                            ? "Incoming call" : $0.state == "active" ? "Call in progress" : "No active call"
                    } ?? calls.callDescription)
                if !calls.connected {
                    Button("Connect Bluetooth call service", action: model.connectCalls).disabled(calls.connecting)
                }
                CallAudioControls(relay: model.callAudio, connected: model.bridge.connected)
                HStack {
                    Button("Answer on Mac") { model.answerCallOnMac() }.disabled(
                        model.phoneCall?.state != "ringing" && !calls.canAnswer)
                    Button("End call", role: .destructive) { model.endCurrentCall() }.disabled(
                        (model.phoneCall?.state ?? "idle") == "idle" && !calls.canEnd)
                }
                HStack {
                    TextField("Phone number", text: $model.dialNumber)
                    Button("Call") { proposedNumber = CallNumber.normalize(model.dialNumber) }
                        .disabled(
                            !calls.connected || calls.callActive || calls.callSetup != 0 || calls.callHeld != 0
                                || CallNumber.normalize(model.dialNumber) == nil)
                }
                Text("tel: links populate this field; dialing requires separate confirmation.").font(.caption)
                    .foregroundStyle(.secondary)
            }.padding(12)
        }
        .alert("Call from phone", isPresented: Binding(get: { proposedNumber != nil }, set: { _ in })) {
            Button("Call") {
                if let proposedNumber { model.dialFromMac(proposedNumber) }; proposedNumber = nil
            }
            Button("Cancel", role: .cancel) { proposedNumber = nil }
        } message: {
            Text(proposedNumber ?? "")
        }
    }
}

struct NotificationActionsView: View {
    let notification: NotificationPosted
    @ObservedObject var controls: DeviceControls
    let available: Bool
    @State private var replying = false
    @State private var token: String?
    @State private var title = ""
    @State private var draft = ""
    var body: some View {
        HStack {
            if notification.canReply, notification.actionToken != nil {
                Button("Reply") {
                    token = notification.actionToken; title = notification.title ?? notification.appName
                    draft = ""; replying = true
                }.disabled(!available || controls.busy)
            }
            if notification.canDismiss == true, let token = notification.actionToken {
                Button("Dismiss on phone") {
                    controls.perform(
                        DeviceCommand(action: .notificationDismiss, key: notification.key, actionToken: token))
                }.disabled(!available || controls.busy)
            }
        }
        .sheet(isPresented: $replying) {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(.headline)
                TextField("Your reply", text: $draft, axis: .vertical).lineLimit(3...6)
                HStack {
                    Button("Cancel") { replying = false }
                    Spacer()
                    Button("Send") {
                        controls.perform(
                            DeviceCommand(
                                action: .notificationReply, text: draft, key: notification.key, actionToken: token))
                        replying = false
                    }.disabled(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf16.count > 4096
                            || !available || controls.busy)
                }
            }.padding(24).frame(width: 440)
        }
    }
}

private struct CallAudioControls: View {
    @ObservedObject var relay: CallAudioRelay
    let connected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(relay.status).font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Request Mac audio") { relay.start() }.disabled(!connected || relay.active || relay.busy)
                Button("Keep audio on phone") { relay.stop() }.disabled(!relay.active && !relay.busy)
            }
            Text(
                "Call controls require a supported Bluetooth call path. BLE call audio is unavailable in this build."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
