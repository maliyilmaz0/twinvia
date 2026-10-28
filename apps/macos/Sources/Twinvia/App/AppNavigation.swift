import Foundation

/// Presentation-only navigation. Pairing URLs and call execution use separate validation paths.
enum AppNavigation: Equatable {
    case calls, contacts, history, screen
    case files(path: String)

    static func handles(_ url: URL) -> Bool {
        ["twinvia", "androfest"].contains(url.scheme?.lowercased() ?? "")
    }

    init?(url: URL) {
        guard Self.handles(url) else { return nil }
        switch url.host?.lowercased() {
        case "calls": self = .calls
        case "contacts": self = .contacts
        case "history": self = .history
        case "screen": self = .screen
        case "files":
            let path =
                URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "path" })?.value ?? ""
            self = .files(path: path)
        default: return nil
        }
    }
}
