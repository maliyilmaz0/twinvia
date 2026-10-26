import TwinviaProtocol
import Combine
import Foundation

enum FileControl: Sendable {
    case offer(FileOffer)
    case accept(FileAccept)
    case complete(FileComplete)
    case cancel(FileCancel)
}

struct FileTransferStatus {
    var fileName = ""
    var bytes: Int64 = 0
    var total: Int64 = 0
    var message = ""
    var busy = false
    var receivedURL: URL?
}

@MainActor
final class FileTransferController: ObservableObject {
    @Published private(set) var status = FileTransferStatus()
    @Published private(set) var incomingOffer: FileOffer?
    private let send: (FileControl) throws -> Void
    private let sendChunk: (FileChunk) throws -> Void
    private let storage: FileStorage
    private var current: FileOffer?
    private var outgoing = false
    private var sentEnd: Int64 = 0
    private var generation = UUID()
    private var lastActivity = Date()
    private var cleanup: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    init(
        send: @escaping (FileControl) throws -> Void, sendChunk: @escaping (FileChunk) throws -> Void,
        directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Twinvia", isDirectory: true)
    ) {
        self.send = send
        self.sendChunk = sendChunk
        storage = FileStorage(directory: directory)
        watchdog = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self else { return }
                if self.status.busy
                    && Date().timeIntervalSince(self.lastActivity) > (self.incomingOffer == nil ? 60 : 300)
                {
                    self.cancel(reason: "File transfer timed out.")
                }
            }
        }
    }

    func sendFile(_ file: LocalFile) {
        guard !status.busy else { return }
        guard file.offer.size <= FileChunk.maxFileBytes else {
            status.message = "File size limit: 2 GiB."; return
        }
        let offer = FileOffer(
            transferId: UUID().uuidString.lowercased(), fileName: file.offer.fileName,
            mimeType: file.offer.mimeType, size: file.offer.size, sha256: file.offer.sha256)
        current = offer
        outgoing = true
        sentEnd = 0
        generation = UUID()
        let token = generation
        lastActivity = Date()
        status = FileTransferStatus(
            fileName: file.offer.fileName, total: file.offer.size, message: "Waiting for approval on phone",
            busy: true)
        Task { @MainActor in
            await cleanup?.value
            guard generation == token else { return }
            do {
                try await storage.beginSending(file)
                guard generation == token else { return }
                try send(.offer(offer))
            } catch { if generation == token { cancel(reason: error.localizedDescription) } }
        }
    }

    func receive(_ control: FileControl) {
        switch control {
        case .offer(let request):
            guard !status.busy, request.size <= FileChunk.maxFileBytes else {
                try? send(
                    .cancel(
                        FileCancel(
                            transferId: request.transferId, reason: "The recipient is busy or the file exceeds 2 GiB."))
                )
                return
            }
            current = request
            outgoing = false
            generation = UUID()
            incomingOffer = request
            lastActivity = Date()
            status = FileTransferStatus(
                fileName: request.fileName, total: request.size, message: "Accept incoming file", busy: true)
        case .accept(let ack):
            guard let current, outgoing, sameID(ack.transferId, current.transferId) else { return }
            guard ack.offset == sentEnd else { cancel(reason: "Could not verify the file location."); return }
            lastActivity = Date()
            status.bytes = ack.offset
            status.message = ack.offset == current.size ? "Phone is verifying the file" : "Sending to phone"
            let token = generation
            Task { @MainActor in
                do {
                    let chunk = try await storage.read(at: ack.offset)
                    guard generation == token else { return }
                    if let chunk {
                        sentEnd = chunk.offset + Int64(chunk.data.count)
                        try sendChunk(FileChunk(transferId: current.transferId, offset: chunk.offset, data: chunk.data))
                    }
                } catch { if generation == token { cancel(reason: error.localizedDescription) } }
            }
        case .complete(let complete):
            guard let current, outgoing, sameID(complete.transferId, current.transferId) else { return }
            guard sentEnd == current.size, complete.sha256 == current.sha256 else {
                cancel(reason: "File verification failed."); return
            }
            finish(message: "Sent to phone · SHA-256 verified")
        case .cancel(let cancel):
            if sameID(cancel.transferId, current?.transferId ?? "") {
                self.cancel(reason: cancel.reason ?? "The other device cancelled the transfer.", notify: false)
            }
        }
    }

    func accept() {
        guard let current, incomingOffer != nil else { return }
        incomingOffer = nil
        let token = generation
        lastActivity = Date()
        status.message = "Receiving from phone"
        Task { @MainActor in
            await cleanup?.value
            guard generation == token else { return }
            do {
                try await storage.beginReceiving(current)
                guard generation == token else { return }
                try send(.accept(FileAccept(transferId: current.transferId, offset: 0)))
                if current.size == 0 { await completeIncoming(token: token) }
            } catch { if generation == token { cancel(reason: error.localizedDescription) } }
        }
    }

    func receiveChunk(_ chunk: FileChunk) {
        guard let current, !outgoing, incomingOffer == nil, sameID(chunk.transferId, current.transferId) else { return }
        let token = generation
        Task { @MainActor in
            do {
                let offset = try await storage.write(chunk)
                guard generation == token else { return }
                status.bytes = offset
                lastActivity = Date()
                if offset == current.size {
                    await completeIncoming(token: token)
                } else {
                    try send(.accept(FileAccept(transferId: current.transferId, offset: offset)))
                }
            } catch { if generation == token { cancel(reason: error.localizedDescription) } }
        }
    }

    private func completeIncoming(token: UUID) async {
        guard let current, generation == token else { return }
        do {
            let url = try await storage.finishReceiving()
            guard generation == token else { return }
            finish(message: "Saved in Downloads/Twinvia · SHA-256 verified", receivedURL: url)
            try? send(.complete(FileComplete(transferId: current.transferId, sha256: current.sha256)))
        } catch { if generation == token { cancel(reason: error.localizedDescription) } }
    }

    func cancel(reason: String = "Transfer cancelled.", notify: Bool = true) {
        let id = current?.transferId
        generation = UUID()
        current = nil
        incomingOffer = nil
        status.busy = false
        status.message = String(reason.prefix(128))
        resetStorage()
        if notify, let id {
            let bounded = String(decoding: reason.utf16.prefix(256), as: UTF16.self)
            try? send(.cancel(FileCancel(transferId: id, reason: bounded)))
        }
    }

    func disconnected() {
        if status.busy { cancel(reason: "Disconnected; the file is incomplete.", notify: false) }
    }

    private func finish(message: String, receivedURL: URL? = nil) {
        generation = UUID()
        current = nil
        incomingOffer = nil
        status.bytes = status.total
        status.message = message
        status.busy = false
        status.receivedURL = receivedURL
        resetStorage()
    }

    private func resetStorage() {
        let previous = cleanup
        cleanup = Task {
            await previous?.value; await storage.reset()
        }
    }

    private func sameID(_ lhs: String, _ rhs: String) -> Bool { lhs.caseInsensitiveCompare(rhs) == .orderedSame }
}
