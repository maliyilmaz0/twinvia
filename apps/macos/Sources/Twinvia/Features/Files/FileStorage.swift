import TwinviaProtocol
import CryptoKit
import Darwin
import Foundation

struct TransferFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// File handles and hashing stay off the UI actor; no complete file is kept in RAM.
actor FileStorage {
    private var source: FileHandle?
    private var sink: FileHandle?
    private var temporary: URL?
    private var sourceURL: URL?
    private var scoped = false
    private var offer: FileOffer?
    private var offset: Int64 = 0
    private var digest = SHA256()
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    func beginSending(_ file: LocalFile) throws {
        guard offer == nil, file.offer.size <= FileChunk.maxFileBytes else {
            throw TransferFailure("The file is busy or exceeds 2 GiB.")
        }
        scoped = file.url.startAccessingSecurityScopedResource()
        sourceURL = file.url
        source = try FileHandle(forReadingFrom: file.url)
        offer = file.offer
    }

    func read(at offset: Int64) throws -> FileChunk? {
        guard let offer, let source, offset >= 0, offset <= offer.size else {
            throw TransferFailure("Invalid file read offset.")
        }
        if offset == offer.size { return nil }
        try source.seek(toOffset: UInt64(offset))
        let count = Int(min(Int64(FileChunk.maxDataBytes), offer.size - offset))
        guard let data = try source.read(upToCount: count), !data.isEmpty else {
            throw TransferFailure("The source file changed during transfer.")
        }
        return FileChunk(transferId: offer.transferId, offset: offset, data: data)
    }

    func beginReceiving(_ offer: FileOffer) throws {
        try offer.validate()
        guard self.offer == nil, offer.size <= FileChunk.maxFileBytes else {
            throw TransferFailure("The file is busy or exceeds 2 GiB.")
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let available =
            try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0
        guard available > offer.size + 16_777_216 else { throw TransferFailure("Not enough free space on Mac.") }
        let temporary = directory.appendingPathComponent(".twinvia-\(UUID().uuidString).part")
        let descriptor = Darwin.open(
            temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw TransferFailure("Could not create a temporary file.") }
        self.temporary = temporary
        sink = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        self.offer = offer
        offset = 0
        digest = SHA256()
    }

    func write(_ chunk: FileChunk) throws -> Int64 {
        guard let offer, let sink, chunk.transferId.lowercased() == offer.transferId.lowercased(),
            chunk.offset == offset, (1...FileChunk.maxDataBytes).contains(chunk.data.count),
            offset + Int64(chunk.data.count) <= offer.size
        else {
            throw TransferFailure("Invalid file chunk or offset.")
        }
        try sink.write(contentsOf: chunk.data)
        digest.update(data: chunk.data)
        offset += Int64(chunk.data.count)
        return offset
    }

    func finishReceiving() throws -> URL {
        guard let offer, let sink, let temporary, offset == offer.size else {
            throw TransferFailure("The file is not complete yet.")
        }
        let hash = digest.finalize().map { String(format: "%02x", $0) }.joined()
        guard hash == offer.sha256 else { throw TransferFailure("SHA-256 mismatch; incomplete file removed.") }
        try sink.synchronize()
        try sink.close()
        self.sink = nil
        let verification = try FileHandle(forReadingFrom: temporary)
        defer { try? verification.close() }
        var storedHash = SHA256()
        var storedSize: Int64 = 0
        while let bytes = try verification.read(upToCount: 65_536), !bytes.isEmpty {
            storedSize += Int64(bytes.count)
            guard storedSize <= offer.size else { throw TransferFailure("The saved file size changed.") }
            storedHash.update(data: bytes)
        }
        let storedDigest = storedHash.finalize().map { String(format: "%02x", $0) }.joined()
        guard storedSize == offer.size, storedDigest == offer.sha256 else {
            throw TransferFailure("The saved file failed verification.")
        }
        let name = offer.fileName as NSString
        for attempt in 0..<10_000 {
            let candidate =
                attempt == 0
                ? offer.fileName
                : "\(name.deletingPathExtension)-\(attempt)"
                    + (name.pathExtension.isEmpty ? "" : ".\(name.pathExtension)")
            let output = directory.appendingPathComponent(candidate)
            do {
                // moveItem never replaces an existing destination, including symlinks.
                try FileManager.default.moveItem(at: temporary, to: output)
                self.temporary = nil
                self.offer = nil
                offset = 0
                return output
            } catch CocoaError.fileWriteFileExists { continue }
        }
        throw TransferFailure("Too many files share this name.")
    }

    func reset() {
        try? source?.close(); source = nil
        try? sink?.close(); sink = nil
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
        if scoped { sourceURL?.stopAccessingSecurityScopedResource() }
        sourceURL = nil
        scoped = false
        temporary = nil
        offer = nil
        offset = 0
        digest = SHA256()
    }
}
