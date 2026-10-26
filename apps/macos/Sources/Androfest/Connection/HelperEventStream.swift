import Foundation

/// Bounded newline-delimited JSON from the child process. Never carries trust decisions.
struct HelperEventStream {
    static let maxBufferedBytes = 32_768
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [[String: Any]] {
        guard data.count <= Self.maxBufferedBytes - buffer.count else { throw Failure.overflow }
        buffer.append(data)
        var records: [[String: Any]] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer[..<end]
            buffer.removeSubrange(...end)
            if let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                records.append(record)
            }
        }
        return records
    }

    enum Failure: Error { case overflow }
}
