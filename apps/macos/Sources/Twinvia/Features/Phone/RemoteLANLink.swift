import Foundation
@preconcurrency import Network
import TwinviaProtocol

@MainActor
protocol RemoteScreenLink: AnyObject {
    var ready: Bool { get }
    var onReady: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func request(detail: Bool, completion: @escaping (Result<RemoteScreen, Error>) -> Void)
    func close()
}

/// A local socket carries only AES-GCM records authorized by the existing pinned BLE session.
@MainActor
final class RemoteLANLink: RemoteScreenLink {
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private(set) var ready = false
    private var connection: NWConnection?
    private var cipher: RemoteFrameCipher?
    private var completion: ((Result<RemoteScreen, Error>) -> Void)?
    private var deadline: Task<Void, Never>?
    private var generation = UUID()

    func connect(credentials: RemoteChannel) throws {
        close(); try credentials.validate()
        guard let host = credentials.host, let number = credentials.port,
            let port = NWEndpoint.Port(rawValue: UInt16(number))
        else { throw Failure.message("No local screen endpoint was provided.") }
        cipher = try RemoteFrameCipher(channel: credentials, mac: true)
        let parameters = NWParameters.tcp
        let next = NWConnection(host: .init(host), port: port, using: parameters)
        connection = next
        let current = generation
        next.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                switch state {
                case .ready: self.deadline?.cancel(); self.ready = true; self.onReady?()
                case .failed:
                    self.fail(
                        "Local screen connection failed. Check Wi-Fi, local-network permission and network isolation.")
                default: break
                }
            }
        }
        armDeadline(); next.start(queue: .main)
    }
    func request(detail: Bool, completion: @escaping (Result<RemoteScreen, Error>) -> Void) {
        guard ready, self.completion == nil, let connection else { return }
        self.completion = completion
        do {
            guard let record = try cipher?.seal(Data((detail ? "detail" : "responsive").utf8)) else {
                throw Failure.message("Screen key is unavailable.")
            }
            let frame = withUnsafeBytes(of: UInt32(record.count).bigEndian) { Data($0) } + record
            let current = generation
            armDeadline()
            connection.send(
                content: frame,
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.generation == current, error != nil else { return }
                        self.fail("The local screen request could not be sent.")
                    }
                })
            receive(count: 4, generation: current) { [weak self] header in
                guard let self else { return }
                let size = header.reduce(0) { ($0 << 8) | Int($1) }
                guard (24...(WireCodec.maxMessageBytes + 24)).contains(size) else {
                    self.fail("Invalid local screen frame size."); return
                }
                self.receive(count: size, generation: current) { [weak self] data in self?.decode(data) }
            }
        } catch { fail(error.localizedDescription) }
    }
    private func receive(count: Int, generation current: UUID, consume: @escaping @MainActor @Sendable (Data) -> Void) {
        connection?.receive(minimumIncompleteLength: count, maximumLength: count) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                guard error == nil, let data, data.count == count else {
                    self.fail("Local screen connection closed or returned an incomplete frame."); return
                }
                consume(data)
            }
        }
    }
    private func decode(_ data: Data) {
        do {
            guard let plain = try cipher?.open(data) else { throw Failure.message("Screen key is unavailable.") }
            let reply = try JSONDecoder().decode(FastScreenReply.self, from: plain)
            guard let screen = reply.screen, reply.error == nil else {
                throw Failure.message(reply.error ?? "No screen was returned.")
            }
            try screen.validate()
            deadline?.cancel(); let callback = completion; completion = nil; callback?(.success(screen))
        } catch { fail(error.localizedDescription) }
    }
    private func armDeadline() {
        deadline?.cancel(); let current = generation
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == current else { return }
            self.fail(
                "Local screen connection timed out. The network may isolate devices; refresh over BLE or reconnect the Wi-Fi lane."
            )
        }
    }
    private func fail(_ message: String) {
        let callback = completion; close(); callback?(.failure(Failure.message(message))); onFailure?(message)
    }
    func close() {
        generation = UUID(); deadline?.cancel(); deadline = nil
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        cipher = nil; completion = nil; ready = false
    }
    private enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
    }
}
