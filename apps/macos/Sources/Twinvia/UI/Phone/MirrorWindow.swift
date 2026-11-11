import AppKit
import SwiftUI
import TwinviaProtocol

@MainActor
enum MirrorWindow {
    private static var window: NSWindow?
    private static var delegate: MirrorWindowDelegate?
    static func show(model: DashboardModel) {
        if window == nil {
            let next = NSWindow(contentViewController: NSHostingController(rootView: MirrorView(model: model)))
            next.title = "Twinvia · Phone mirror"
            next.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            next.titlebarAppearsTransparent = true
            next.setContentSize(NSSize(width: 430, height: 850))
            next.minSize = NSSize(width: 360, height: 600)
            next.isReleasedWhenClosed = false
            next.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            next.setFrameAutosaveName("TwinviaPhoneMirror")
            delegate = MirrorWindowDelegate(remote: model.remoteControl)
            next.delegate = delegate
            next.center()
            window = next
        }
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class MirrorWindowDelegate: NSObject, NSWindowDelegate {
    let remote: RemoteControlModel
    init(remote: RemoteControlModel) { self.remote = remote }
    func windowWillClose(_ notification: Notification) { remote.closeMirror() }
    func windowDidMiniaturize(_ notification: Notification) { remote.setPreview(false) }
}

struct MirrorView: View {
    @ObservedObject private var remote: RemoteControlModel
    @ObservedObject private var privacy: PrivacyBreak
    @State private var zoom = 1.0
    @ObservedObject private var bridge: BridgeClient
    @AppStorage("playfulMotion") private var playfulMotion = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var typedText = ""
    @State private var showConnection = false
    @AppStorage("callBluetoothPeerAddress") private var phoneAddress = ""
    @State private var showKeyboard = false
    @FocusState private var typingFocused: Bool

    init(model: DashboardModel) { remote = model.remoteControl; bridge = model.bridge; privacy = model.privacy }
    private var available: Bool {
        bridge.connected && !privacy.active && bridge.peerCapabilities.contains("remote.screen")
    }
    private var inputAvailable: Bool { available && remote.controlAllowed != false }
    private var modern: Bool { bridge.peerCapabilities.contains("remote.screen.v2") }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: available ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .foregroundStyle(available ? .green : .secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bridge.peerName ?? "Phone mirror").font(.headline).lineLimit(1)
                    Text(privacy.active ? "Privacy break" : available ? "Connected" : "Not connected").font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showConnection.toggle()
                } label: {
                    Image(systemName: remote.fastConnected ? "bolt.horizontal.fill" : "bolt.horizontal")
                }
                .help("Choose Wi-Fi or Bluetooth screen connection").accessibilityLabel("Screen connection")
                .popover(isPresented: $showConnection) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Choose a screen connection").font(.headline)
                        Button("Use Bluetooth LE") {
                            remote.useBLE(); showConnection = false
                        }
                        Text(
                            "Wi-Fi screen: sharper images over an existing shared local network. The normal bridge stays on BLE."
                        )
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        Button("Connect Wi-Fi screen") {
                            remote.connectLAN(); showConnection = false
                        }
                        .disabled(
                            !available || remote.busy || remote.loadingFrame
                                || !bridge.peerCapabilities.contains("remote.screen.lan"))
                        Divider()
                        Text("Bluetooth Classic · experimental").font(.headline)
                        Text(
                            "Pair your phone in macOS Bluetooth settings first. This screen lane uses Classic Bluetooth; controls keep using the existing connection."
                        )
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        Picker("Paired phone", selection: $phoneAddress) {
                            Text("Choose a phone").tag("")
                            ForEach(RemoteFastLink.phones) { phone in Text(phone.name).tag(phone.id) }
                        }
                        Button("Connect screen lane") {
                            remote.connectFast(address: phoneAddress); showConnection = false
                        }
                        .disabled(phoneAddress.isEmpty || !available || !modern || remote.busy || remote.loadingFrame)
                    }.padding().frame(width: 320)
                }
                Menu {
                    Picker("Image quality", selection: $remote.quality) {
                        ForEach(RemoteControlModel.Quality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }.disabled(!modern)
                    Divider()
                    Picker("View scale", selection: $zoom) {
                        Text("Fit").tag(1.0); Text("150%").tag(1.5); Text("200%").tag(2.0)
                    }
                    Text("At 150%/200%, drag pans the image. Use the arrows to scroll the phone.")
                    Text("Detail uses more bandwidth and can be slower over BLE.")
                    if !modern { Text("Install the matching Android build to enable Detail and keyboard input.") }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Image quality").accessibilityLabel("Image quality")
                Button {
                    remote.requestFrame()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh screen").accessibilityLabel("Refresh screen").keyboardShortcut("r")
                .disabled(!available || remote.busy)
            }.padding(.horizontal, 18).padding(.vertical, 12)
            Divider()
            if privacy.active { PrivacyBreakView(privacy: privacy).padding(12) }
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if remote.image == nil { AuroraBackdrop() }
                    if let image = remote.image, remote.imageWidth > 0, remote.imageHeight > 0 {
                        let scale = min(
                            geometry.size.width / Double(remote.imageWidth),
                            geometry.size.height / Double(remote.imageHeight))
                        let width = Double(remote.imageWidth) * scale * zoom
                        let height = Double(remote.imageHeight) * scale * zoom
                        ScrollView([.horizontal, .vertical]) {
                            Image(nsImage: image).resizable().interpolation(.high)
                                .frame(width: width, height: height)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture().onEnded { value in
                                        guard inputAvailable && !remote.busy else { return }
                                        remote.tap(x: value.location.x / width, y: value.location.y / height)
                                    }
                                )
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 10).onEnded { value in
                                        guard inputAvailable && !remote.busy else { return }
                                        remote.swipe(
                                            from: CGPoint(
                                                x: value.startLocation.x / width, y: value.startLocation.y / height),
                                            to: CGPoint(x: value.location.x / width, y: value.location.y / height))
                                    }, including: zoom == 1 ? .all : .none
                                )
                                .overlay(
                                    MirrorScrollCapture(enabled: inputAvailable && zoom == 1 && !remote.busy) {
                                        remote.scroll($0)
                                    }
                                )
                                .accessibilityLabel(
                                    "Phone screen. Click to tap. At Fit, drag or scroll to swipe; when zoomed, drag to pan."
                                )
                                .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        }
                    } else {
                        VStack(spacing: 18) {
                            ConnectionOrbit(connected: available)
                            Text("Ready when you are").font(.system(.title2, design: .rounded, weight: .bold))
                            Text("Approve screen viewing on your phone, then refresh here.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Label("Your phone stays in control", systemImage: "lock.shield")
                                .font(.caption).foregroundStyle(FestTheme.lime)
                        }.padding(32)

                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Never retain a disappearing private screen for a decorative transition.
                    .transaction { $0.animation = nil }
            }
            Divider()
            HStack(spacing: 16) {
                control("Back", "chevron.backward", .remoteBack)
                control("Home", "house", .remoteHome)
                control("Notifications", "bell", .remoteNotifications)
                Button {
                    remote.scroll(.up)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .help("Scroll phone up").accessibilityLabel("Scroll phone up").disabled(!inputAvailable || remote.busy)
                Button {
                    remote.scroll(.down)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .help("Scroll phone down").accessibilityLabel("Scroll phone down").disabled(
                    !inputAvailable || remote.busy)
                Button {
                    showKeyboard.toggle()
                } label: {
                    Image(systemName: "keyboard")
                }
                .help(modern ? "Type on phone" : "Update the Android app to enable keyboard input").accessibilityLabel(
                    "Type on phone"
                ).disabled(!inputAvailable || remote.busy || !modern)
                .popover(isPresented: $showKeyboard) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Type on phone").font(.headline)
                        Text("Focus a text field on the phone first.").font(.caption)
                        TextField("Text", text: $typedText).focused($typingFocused).onSubmit(sendText)
                        HStack {
                            Button("Backspace") { remote.key("backspace") }
                            Button("Enter") { remote.key("enter") }
                            Spacer()
                            Button("Send", action: sendText).disabled(typedText.isEmpty || typedText.utf16.count > 1024)
                        }.disabled(remote.busy)
                    }.padding().frame(width: 340)
                        .onAppear { typingFocused = true }
                        .onDisappear { typedText = "" }
                }
                Spacer()
                Button {
                    remote.setPreview(!remote.preview)
                } label: {
                    Image(systemName: remote.preview ? "pause.fill" : "play.fill")
                        .contentTransition(reduceMotion || !playfulMotion ? .identity : .symbolEffect(.replace))
                }.help(remote.preview ? "Pause preview" : "Refresh preview automatically")
                    .accessibilityLabel(remote.preview ? "Pause preview" : "Start preview")
                    .disabled(!available)
            }.padding(16)
            HStack(alignment: .top, spacing: 8) {
                if remote.busy || remote.loadingFrame { ProgressView().controlSize(.mini) }
                Text(remote.message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Spacer(minLength: 0)
                Text(remote.quality.rawValue).font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(FestTheme.background)
        .preferredColorScheme(.dark).tint(FestTheme.violet)
        .animation(reduceMotion || !playfulMotion ? nil : .easeOut(duration: 0.2), value: available)
        .modifier(TwinviaMotion())
        .onAppear {
            remote.configure(supportsDetail: modern, supportsLAN: bridge.peerCapabilities.contains("remote.screen.lan"))
        }
        .onChange(of: bridge.connected) { _, _ in
            remote.configure(supportsDetail: modern, supportsLAN: bridge.peerCapabilities.contains("remote.screen.lan"))
        }
        .onChange(of: privacy.active) { _, value in if value { showKeyboard = false; typedText = "" } }
        .onChange(of: remote.controlAllowed) { _, value in if value == false { showKeyboard = false; typedText = "" } }
        .onChange(of: remote.quality) { _, _ in if !remote.busy && available { remote.requestFrame() } }
    }
    private func control(_ label: String, _ icon: String, _ action: DeviceAction) -> some View {
        Button {
            remote.request(action)
        } label: {
            Image(systemName: icon)
        }
        .help(label).accessibilityLabel(label).disabled(!inputAvailable || remote.busy)
    }
    private func sendText() {
        guard inputAvailable, !typedText.isEmpty, typedText.utf16.count <= 1024, !remote.busy else { return }
        remote.type(typedText); typedText = ""
    }
}
