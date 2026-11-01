import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class StartupSettings: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var busy = false
    @Published private(set) var message = ""
    private let service = SMAppService.mainApp
    let installed =
        Bundle.main.bundleURL.pathExtension == "app"
        && Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Applications"
    init() { refresh() }
    func refresh() {
        enabled = service.status == .enabled
        needsApproval = service.status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        guard installed, !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false; refresh() }
            do {
                // Keep the non-Sendable service on MainActor on older macOS SDKs too.
                // The synchronous API returns without waiting for process termination.
                if value { try service.register() } else { try service.unregister() }
                message = ""
            } catch { message = error.localizedDescription }
        }
    }
}

struct StartupSettingsView: View {
    @StateObject private var startup = StartupSettings()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        GroupBox("Ready when your Mac is") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(
                    "Launch Twinvia at login", isOn: Binding(get: { startup.enabled }, set: { startup.setEnabled($0) })
                )
                .disabled(!startup.installed || startup.busy)
                Text(
                    "An optional background companion. Closing a window leaves the menu bar available; Quit stops Twinvia."
                )
                .font(.caption).foregroundStyle(.secondary)
                if !startup.installed { Text("Install Twinvia in Applications to enable login launch.").font(.caption) }
                if startup.needsApproval {
                    Button("Review in Login Items settings") { SMAppService.openSystemSettingsLoginItems() }
                }
                if !startup.message.isEmpty { Text(startup.message).font(.caption) }
            }.padding(12)
        }.onAppear { startup.refresh() }
            .onChange(of: phase) { _, value in if value == .active { startup.refresh() } }
    }
}
