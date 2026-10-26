import TwinviaProtocol
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct LocalFile: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let offer: FileOffer

    static func inspect(_ url: URL) throws -> LocalFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let resource = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard resource.isRegularFile == true else { throw FileError.notAFile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            size += Int64(chunk.count)
            hash.update(data: chunk)
        }
        let id = UUID()
        let offer = FileOffer(
            transferId: id.uuidString.lowercased(),
            fileName: url.lastPathComponent,
            mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
            size: size,
            sha256: hash.finalize().map { String(format: "%02x", $0) }.joined()
        )
        try offer.validate()
        return LocalFile(id: id, url: url, offer: offer)
    }
}

enum FileError: LocalizedError {
    case notAFile
    var errorDescription: String? { "Choose a file instead of a folder." }
}
