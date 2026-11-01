import SwiftUI

private struct PlayfulMotionKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var twinviaPlayfulMotion: Bool {
        get { self[PlayfulMotionKey.self] }
        set { self[PlayfulMotionKey.self] = newValue }
    }
}

/// Shared motion stays on the presentation side; it never schedules bridge work.
struct TwinviaMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("playfulMotion") private var playfulMotion = true
    func body(content: Content) -> some View {
        content.environment(\.twinviaPlayfulMotion, playfulMotion && !systemReduceMotion)
    }
}

struct AuroraBackdrop: View {
    @Environment(\.twinviaPlayfulMotion) private var playfulMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var visible = false
    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 12, paused: reduceMotion || !playfulMotion || !visible || phase != .active)
        ) {
            time in
            let drift = reduceMotion || !playfulMotion ? 0 : sin(time.date.timeIntervalSinceReferenceDate / 8)
            GeometryReader { geometry in
                ZStack {
                    FestTheme.background
                    Ellipse().fill(FestTheme.violet.opacity(0.16))
                        .frame(width: geometry.size.width * 0.9, height: 280)
                        .blur(radius: 70).offset(x: 100 + drift * 28, y: -geometry.size.height / 2)
                    Ellipse().fill(FestTheme.lime.opacity(0.07))
                        .frame(width: 260, height: 260)
                        .blur(radius: 70).offset(x: -geometry.size.width / 2, y: 150 - drift * 24)
                }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { visible = true }.onDisappear { visible = false }
    }
}

struct FestTileButtonStyle: ButtonStyle {
    @Environment(\.twinviaPlayfulMotion) private var playfulMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 20).stroke(
                    FestTheme.violet.opacity(hovered && enabled ? 0.7 : 0), lineWidth: 1)
            )
            .shadow(color: FestTheme.violet.opacity(hovered && enabled ? 0.12 : 0), radius: 12, y: 4)
            .scaleEffect(
                reduceMotion || !playfulMotion || !enabled ? 1 : configuration.isPressed ? 0.97 : hovered ? 1.015 : 1
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed
            )
            .animation(reduceMotion || !playfulMotion ? nil : .easeOut(duration: 0.18), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct MotionSettingsView: View {
    @AppStorage("playfulMotion") private var playfulMotion = true
    var body: some View {
        GroupBox("Make it yours") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Playful motion", isOn: $playfulMotion)
                Text("Animated auroras, connection orbits and springy controls. Reduce Motion takes priority.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
    }
}

struct FeatureLaunchpad: View {
    let open: (Int) -> Void
    private let features: [(Int, String, String, String)] = [
        (6, "Phone mirror", "A little window into your phone.", "iphone.radiowaves.left.and.right"),
        (1, "Files", "Drop it here. Take it there.", "arrow.up.arrow.down"),
        (2, "Calls", "Keep the conversation going.", "phone"),
        (3, "Notifications", "Stay in the loop.", "bell"),
        (4, "Contacts", "Your people, close at hand.", "person.2"),
        (5, "Call history", "Pick up where you left off.", "clock.arrow.circlepath"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your everyday superpowers").font(.system(.title2, design: .rounded, weight: .bold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(features, id: \.0) { feature in
                    Button {
                        open(feature.0)
                    } label: {
                        FestCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: feature.3).font(.title2).foregroundStyle(FestTheme.lime)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").foregroundStyle(FestTheme.violet)
                                }.accessibilityHidden(true)
                                Text(feature.1).font(.headline)
                                Text(feature.2).font(.callout).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(FestTileButtonStyle())
                }
            }
        }
    }
}
