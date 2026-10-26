import Foundation

enum CallNumber {
    /// Reject USSD, extensions, pauses, queries and embedded commands. Calling still requires user confirmation.
    static func normalize(_ raw: String) -> String? {
        guard raw.utf16.count <= 128 else { return nil }
        let allowed = CharacterSet(charactersIn: "+0123456789 ()-.")
        guard raw.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let value = raw.filter { !" ()-.".contains($0) }
        return value.range(of: "^\\+?[0-9]{3,20}$", options: .regularExpression) != nil ? value : nil
    }
    static func from(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["tel", "callto"].contains(scheme) else { return nil }
        var raw = String(url.absoluteString.dropFirst(scheme.count + 1))
        if raw.hasPrefix("//") { raw.removeFirst(2) }
        guard let decoded = raw.removingPercentEncoding else { return nil }
        return normalize(decoded)
    }
}
