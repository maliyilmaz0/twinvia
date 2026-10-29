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
    @ObservedObject private var bridge: BridgeClient
    @State private var typedText = ""
    @State private var showConnection = false
    @AppStorage("callBluetoothPeerAddress") private var phoneAddress = ""
    @State private var showKeyboard = false
    @FocusState private var typingFocused: Bool

    init(model: DashboardModel) { remote = model.remoteControl; bridge = model.bridge }
    private var available: Bool { bridge.connected && bridge.peerCapabilities.contains("remote.screen") }
    private var modern: Bool { bridge.peerCapabilities.contains("remote.screen.v2") }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: available ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .foregroundStyle(available ? .green : .secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bridge.peerName ?? "Phone mirror").font(.headline).lineLimit(1)
                    Text(available ? "Connected" : "Not connected").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    showConnection.toggle()
                } label: {
                    Image(systemName: remote.fastConnected ? "bolt.horizontal.fill" : "bolt.horizontal")
                }
                .help("Separate Bluetooth screen lane").accessibilityLabel("Bluetooth Classic screen lane")
                .popover(isPresented: $showConnection) {
                    VStack(alignment: .leading, spacing: 12) {
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
                        .disabled(phoneAddress.isEmpty || !available || !modern || remote.busy)
                    }.padding().frame(width: 320)
                }
                Menu {
                    Picker("Image quality", selection: $remote.quality) {
                        ForEach(RemoteControlModel.Quality.allCases, id: \.self) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }.disabled(!modern)
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
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    if let image = remote.image, remote.imageWidth > 0, remote.imageHeight > 0 {
                        let scale = min(
                            geometry.size.width / Double(remote.imageWidth),
                            geometry.size.height / Double(remote.imageHeight))
                        let width = Double(remote.imageWidth) * scale
                        let height = Double(remote.imageHeight) * scale
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: width, height: height)
                            .contentShape(Rectangle())
                            .gesture(
                                SpatialTapGesture().onEnded { value in
                                    guard available && !remote.busy else { return }
                                    remote.tap(x: value.location.x / width, y: value.location.y / height)
                                }
                            )
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 10).onEnded { value in
                                    guard available && !remote.busy else { return }
                                    remote.swipe(
                                        from: CGPoint(
                                            x: value.startLocation.x / width, y: value.startLocation.y / height),
                                        to: CGPoint(x: value.location.x / width, y: value.location.y / height))
                                }
                            )
                            .accessibilityLabel("Phone screen. Click to tap; drag to swipe.")
                    } else {
                        ContentUnavailableView(
                            "Ready when you are", systemImage: "iphone",
                            description: Text(
                                "On your phone, approve screen viewing and optional touch control, then refresh here.")
                        )
                        .foregroundStyle(.white)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 22) {
                control("Back", "chevron.backward", .remoteBack)
                control("Home", "house", .remoteHome)
                control("Notifications", "bell", .remoteNotifications)
                Button {
                    showKeyboard.toggle()
                } label: {
                    Image(systemName: "keyboard")
                }
                .help(modern ? "Type on phone" : "Update the Android app to enable keyboard input").accessibilityLabel(
                    "Type on phone"
                ).disabled(!available || remote.busy || !modern)
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
        .background(.regularMaterial)
        .onAppear { remote.configure(supportsDetail: modern) }
        .onChange(of: bridge.connected) { _, _ in remote.configure(supportsDetail: modern) }
        .onChange(of: remote.quality) { _, _ in if !remote.busy && available { remote.requestFrame() } }
    }
    private func control(_ label: String, _ icon: String, _ action: DeviceAction) -> some View {
        Button {
            remote.request(action)
        } label: {
            Image(systemName: icon)
        }
        .help(label).accessibilityLabel(label).disabled(!available || remote.busy)
    }
    private func sendText() {
        guard !typedText.isEmpty, typedText.utf16.count <= 1024, !remote.busy else { return }
        remote.type(typedText); typedText = ""
    }
}
