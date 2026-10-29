import Combine
import Foundation
@preconcurrency import Sparkle
import SwiftUI

/// Sparkle verifies the Ed25519 signature before extraction and owns replacement/relaunch.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    private var observations = Set<AnyCancellable>()

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main).sink { [weak self] value in
                MainActor.assumeIsolated { self?.canCheck = value }
            }.store(in: &observations)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main).sink { [weak self] value in
                MainActor.assumeIsolated { self?.automaticChecks = value }
            }.store(in: &observations)
    }

    func setAutomaticChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func check() { controller.checkForUpdates(nil) }
}

struct UpdateSettingsView: View {
    @ObservedObject private var updater = AppUpdater.shared
    var body: some View {
        GroupBox("Software updates") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(
                            "Twinvia \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")"
                        )
                        Text("Signed updates from GitHub Releases. Installation requires your approval.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for updates…", action: updater.check).disabled(!updater.canCheck)
                }
                Toggle(
                    "Check automatically",
                    isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
            }.padding(12)
        }
    }
}
