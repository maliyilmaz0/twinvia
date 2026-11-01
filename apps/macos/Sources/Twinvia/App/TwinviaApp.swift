import AppKit
import SwiftUI

struct TwinviaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: DashboardModel

    init() {
        let sharedModel = DashboardModel()
        _model = StateObject(wrappedValue: sharedModel)
        AppDelegate.model = sharedModel
    }

    var body: some Scene {
        MenuBarExtra {
            TrayView(model: model)
        } label: {
            TrayLabel(bridge: model.bridge, calls: model.calls, transfers: model.transfers)
        }
        .menuBarExtraStyle(.window)
    }
}

@main
enum TwinviaEntry {
    @MainActor
    static func main() {
        #if DEBUG
            if let index = CommandLine.arguments.firstIndex(of: "--bridge-probe-directory"),
                CommandLine.arguments.count > index + 1
            {
                BridgeProbe.run(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
                return
            }
        #endif
        TwinviaApp.main()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: DashboardModel?
    private var workspaceObservers: [NSObjectProtocol] = []
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let model = Self.model else { return }
        urls.forEach(model.handleURL)
        if urls.contains(where: { $0.host == "screen" }) {
            MirrorWindow.show(model: model)
        } else {
            DashboardWindow.show(model: model)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        _ = AppUpdater.shared
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in Self.model?.systemWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in Self.model?.systemDidWake() }
            },
        ]
        #if DEBUG
            if CommandLine.arguments.contains("--call-audio-engine-test") {
                Self.model?.callAudio.selfTestLocalEngine()
            }
        #endif
        if let index = CommandLine.arguments.firstIndex(of: "--phone-section"), CommandLine.arguments.count > index + 1,
            let model = Self.model, let url = URL(string: "androfest://" + CommandLine.arguments[index + 1]),
            ["contacts", "history", "files", "calls", "screen"].contains(url.host ?? "")
        {
            model.handleURL(url)
            DashboardWindow.show(model: model)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        Self.model?.applicationWillTerminate()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

private struct TrayLabel: View {
    @ObservedObject var bridge: BridgeClient
    @ObservedObject var calls: HandsFreeController
    @ObservedObject var transfers: FileTransferController

    var body: some View {
        Label {
            Text("Twinvia · \(bridge.connected ? "Connected" : "Waiting for connection")")
        } icon: {
            if calls.canAnswer {
                Image(systemName: "phone.arrow.down.left.fill")
            } else if transfers.incomingOffer != nil {
                Image(systemName: "tray.and.arrow.down.fill")
            } else {
                Image("TrayMark").renderingMode(.template)
                    .resizable().scaledToFit().frame(width: 18, height: 18)
                    .opacity(bridge.connected ? 1 : 0.5)
            }
        }
    }
}

/// One on-demand SwiftUI window, backed by the same model as the tray.
/// Keeping it outside the scene list also prevents launch/restoration windows on macOS 14.
@MainActor
private enum DashboardWindowStorage {
    static var window: NSWindow?
}

@MainActor
enum DashboardWindow {
    static func show(model: DashboardModel) {
        if DashboardWindowStorage.window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: DashboardView(model: model)))
            window.title = "Twinvia · Control center"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 820, height: 760))
            window.minSize = NSSize(width: 740, height: 620)
            window.isReleasedWhenClosed = false
            // Explicit opens follow the user; remote call/status updates never activate this window.
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            DashboardWindowStorage.window = window
        }
        DashboardWindowStorage.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
