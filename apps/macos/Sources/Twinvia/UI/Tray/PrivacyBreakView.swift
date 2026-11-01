import SwiftUI

struct PrivacyBreakView: View {
    @ObservedObject var privacy: PrivacyBreak
    var body: some View {
        FestCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(
                        privacy.active ? "Privacy break is on" : "Take a privacy break", systemImage: "hand.raised.fill"
                    )
                    .font(.headline).foregroundStyle(privacy.active ? FestTheme.lime : FestTheme.violet)
                    Spacer()
                    if privacy.active {
                        Button("Resume", action: privacy.resume)
                    } else {
                        Menu("Pause sharing") {
                            ForEach(PrivacyBreak.Duration.allCases, id: \.self) { duration in
                                Button("\(duration.rawValue) minutes") { privacy.start(duration) }
                            }
                        }
                    }
                }
                if let until = privacy.until {
                    Text("Paused until \(until.formatted(date: .omitted, time: .shortened)).")
                        .font(.callout).monospacedDigit()
                }
                Text(
                    "Pause clipboard, phone notifications and mirror access on this Mac. Calls and file transfers continue. Skipped content is not replayed on resume."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
