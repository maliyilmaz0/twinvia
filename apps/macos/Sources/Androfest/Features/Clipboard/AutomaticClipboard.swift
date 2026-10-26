import AppKit
import AndrofestProtocol
import Combine
import ImageIO
import CryptoKit
import Foundation

/// Watches copy operations, applies remote text immediately and never echoes its own writes.
@MainActor
final class AutomaticClipboard: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "Clipboard sync waiting for connection"
    private let pasteboard: NSPasteboard
    private let canSend: () -> Bool
    private let send: (String) throws -> String
    private let saveEnabled: (Bool) -> Void
    private var changeCount: Int
    private var lastText: String?
    private var pending: [String: Date] = [:]
    private var latestRequest: String?
    private var imageTask: Task<Void, Never>?
    private var lastImage: Data?
    private let sendImage: ((Data, String) async throws -> Void)?
    private var watcher: Task<Void, Never>?
    private(set) var sent = 0
    private(set) var applied = 0
    private(set) var echoesSuppressed = 0
    #if DEBUG
        private var diagnosticData: Data?
        private var diagnosticTime = Date.distantPast
    #endif

    init(
        pasteboard: NSPasteboard = .general, enabled: Bool = true, automaticallyPoll: Bool = true,
        canSend: @escaping () -> Bool, saveEnabled: @escaping (Bool) -> Void = { _ in },
        sendImage: ((Data, String) async throws -> Void)? = nil,
        send: @escaping (String) throws -> String
    ) {
        self.pasteboard = pasteboard; self.enabled = enabled; self.canSend = canSend
        self.saveEnabled = saveEnabled; self.send = send; self.sendImage = sendImage
        changeCount = pasteboard.changeCount
        if automaticallyPoll {
            watcher = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    self?.poll()
                }
            }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value; saveEnabled(value)
        imageTask?.cancel(); imageTask = nil; lastImage = nil
        changeCount = pasteboard.changeCount; lastText = nil
        status = value ? "Automatic clipboard sync enabled" : "Automatic clipboard sync disabled"
    }

    func poll() {
        #if DEBUG
            defer { writeDiagnostics() }
        #endif
        if let latestRequest, let deadline = pending[latestRequest], Date() >= deadline {
            status = "Phone clipboard acknowledgement timed out"
        }
        pending = pending.filter { Date() < $0.value }
        guard enabled else { changeCount = pasteboard.changeCount; return }
        guard canSend() else {
            changeCount = pasteboard.changeCount; status = "Clipboard sync waiting for connection"; return
        }
        if status == "Clipboard sync waiting for connection" { status = "Automatic clipboard sync enabled" }
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pasteboard.availableType(from: [concealed]) == nil else { return }
        if pasteboard.availableType(from: [.png, .tiff]) != nil {
            lastText = nil
            guard let sendImage else { status = "Phone does not support image clipboard"; return }
            guard let png = Self.imagePNG(from: pasteboard) else {
                status = "Image clipboard limit: 20 MB / 16 megapixels"; return
            }
            let hash = Data(SHA256.hash(data: png))
            guard hash != lastImage else { echoesSuppressed += 1; return }
            lastImage = hash
            imageTask?.cancel()
            let id = UUID().uuidString.lowercased()
            // BLE is deliberately rate-limited. Do not expire a valid image
            // acknowledgement using the old fast-link text deadline.
            pending = [id: Date().addingTimeInterval(max(45, min(900, Double(png.count) / 2500 + 30)))]
            latestRequest = id; sent += 1
            status = "Syncing clipboard image to phone"
            imageTask = Task { @MainActor [weak self] in
                do { try await sendImage(png, id) } catch {
                    guard !Task.isCancelled, self?.latestRequest == id else { return }
                    self?.lastImage = nil
                    self?.pending.removeValue(forKey: id)
                    self?.status = "Could not sync clipboard image: \(error.localizedDescription)"
                }
            }
            return
        }
        lastImage = nil
        imageTask?.cancel(); imageTask = nil
        guard let text = pasteboard.string(forType: .string), !text.isEmpty, text.utf16.count <= 16_384 else { return }
        guard text != lastText else { echoesSuppressed += 1; return }
        lastText = text
        do {
            let id = try send(text)
            pending = [id: Date().addingTimeInterval(30)]; latestRequest = id; sent += 1
            status = "Syncing clipboard to phone"
        } catch { status = "Could not sync clipboard: \(error.localizedDescription)" }
    }

    static func imagePNG(from board: NSPasteboard) -> Data? {
        guard let sourceData = board.data(forType: .png) ?? board.data(forType: .tiff),
            sourceData.count <= 80 * 1024 * 1024,
            let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
            let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = info[kCGImagePropertyPixelWidth] as? Int,
            let height = info[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 16_777_216
        else { return nil }
        if board.availableType(from: [.png]) != nil {
            return sourceData.count <= ClipboardImageChunk.maxImageBytes ? sourceData : nil
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
            png.count <= ClipboardImageChunk.maxImageBytes
        else { return nil }
        return png
    }

    func disconnected() { imageTask?.cancel(); imageTask = nil; pending.removeAll(); lastImage = nil }

    func receive(_ text: String) {
        guard enabled, canSend(), !text.isEmpty, text.utf16.count <= 16_384 else { return }
        guard pasteboard.string(forType: .string) != text else { lastText = text; return }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        changeCount = pasteboard.changeCount; lastText = text
        applied += 1
        status = "Phone clipboard synced to Mac"
    }

    func receive(_ result: CommandResult) {
        guard pending.removeValue(forKey: result.requestId) != nil, latestRequest == result.requestId else { return }
        status = result.success ? "Mac clipboard synced to phone" : result.message
    }

    #if DEBUG
        private func writeDiagnostics() {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.androfest.macos")
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let value: [String: Any] = [
                "enabled": enabled, "connected": canSend(), "sent": sent,
                "applied": applied, "echoesSuppressed": echoesSuppressed, "pending": pending.count, "status": status,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
                guard data != diagnosticData || Date().timeIntervalSince(diagnosticTime) >= 5 else { return }
                diagnosticData = data; diagnosticTime = Date()
                try? data.write(to: directory.appendingPathComponent("clipboard-status.json"), options: .atomic)
            }
        }
    #endif
}
