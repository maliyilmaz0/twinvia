import Foundation
@preconcurrency import IOBluetooth
import TwinviaProtocol

/// Optional Classic Bluetooth lane; all screen bytes use a key issued over pinned TLS.
@MainActor
final class RemoteFastLink: NSObject, IOBluetoothDeviceAsyncCallbacks, IOBluetoothRFCOMMChannelDelegate {
    struct PairedPhone: Identifiable { let id: String; let name: String }
    static var phones: [PairedPhone] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap {
            guard let address = $0.addressString else { return nil }
            return PairedPhone(id: address, name: $0.name ?? address)
        }
    }
    var onReady: (() -> Void)?
    var onFailure: ((String) -> Void)?
    nonisolated private let ingress = RemoteIngressBudget()
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var cipher: RemoteFrameCipher?
    private var buffer = Data()
    private var completion: ((Result<RemoteScreen, Error>) -> Void)?
    private var deadline: Task<Void, Never>?
    private(set) var ready = false
    private var generation = UUID()

    func connect(address: String, credentials: RemoteChannel) throws {
        close()
        guard let phone = IOBluetoothDevice(addressString: address), phone.isPaired() else {
            throw LinkError.message("Pair this phone in macOS Bluetooth settings first.")
        }
        cipher = try RemoteFrameCipher(channel: credentials, mac: true)
        device = phone
        armDeadline()
        guard phone.performSDPQuery(self) == kIOReturnSuccess else {
            throw LinkError.message("Could not discover the phone's screen service.")
        }
    }
    nonisolated func remoteNameRequestComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {}
    nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        let address = device?.addressString
        Task { @MainActor [weak self] in
            guard let self, self.device?.addressString == address else { return }
            self.openChannel(status: status)
        }
    }
    private func openChannel(status: IOReturn) {
        var uuid = UUID(uuidString: RemoteChannel.serviceID)!.uuid
        let service = withUnsafeBytes(of: &uuid) { IOBluetoothSDPUUID(bytes: $0.baseAddress, length: 16) }
        var id: BluetoothRFCOMMChannelID = 0
        guard status == kIOReturnSuccess, let record = device?.getServiceRecord(for: service),
            record.getRFCOMMChannelID(&id) == kIOReturnSuccess,
            device?.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: self) == kIOReturnSuccess
        else { fail("The phone's Classic screen service could not be opened."); return }
    }
    nonisolated func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        let id = channel?.getObjectID()
        Task { @MainActor [weak self] in
            guard let self, self.channel?.getObjectID() == id else { return }
            guard status == kIOReturnSuccess else { self.fail("Bluetooth screen lane failed to connect."); return }
            self.deadline?.cancel(); self.ready = true; self.onReady?()
        }
    }
    nonisolated func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        let id = channel?.getObjectID()
        Task { @MainActor [weak self] in
            guard let self, self.channel?.getObjectID() == id else { return }
            self.fail("Bluetooth Classic screen lane disconnected. Refresh over BLE or reconnect it.")
        }
    }
    nonisolated func rfcommChannelData(
        _ channel: IOBluetoothRFCOMMChannel!, data pointer: UnsafeMutableRawPointer!, length: Int
    ) {
        guard let pointer else { return }
        let budget = ingress
        switch budget.reserve(length) {
        case .ignored: return
        case .overflow(let generation):
            Task { @MainActor [weak self] in
                guard budget.matches(generation) else { return }
                self?.fail("Bluetooth screen input exceeded its bounded queue.")
            }
        case .chunk(let ticket):
            let bytes = Data(bytes: pointer, count: length)
            let id = channel?.getObjectID()
            Task { @MainActor [weak self] in
                defer { budget.release(ticket) }
                guard let self, budget.matches(ticket.generation), self.channel?.getObjectID() == id else { return }
                self.receive(bytes)
            }
        }
    }

    func request(detail: Bool, completion: @escaping (Result<RemoteScreen, Error>) -> Void) {
        guard ready, self.completion == nil, let channel else { return }
        self.completion = completion
        do {
            guard let sealed = try cipher?.seal(Data((detail ? "detail" : "responsive").utf8)) else {
                throw LinkError.message("Screen key is unavailable.")
            }
            var frame = withUnsafeBytes(of: UInt32(sealed.count).bigEndian) { Data($0) } + sealed
            let status = frame.withUnsafeMutableBytes { channel.writeSync($0.baseAddress, length: UInt16($0.count)) }
            guard status == kIOReturnSuccess else { throw LinkError.message("Screen request could not be sent.") }
            armDeadline()
        } catch { fail(error.localizedDescription) }
    }
    private func receive(_ bytes: Data) {
        guard buffer.count + bytes.count <= WireCodec.maxMessageBytes + 28 else {
            fail("Screen frame exceeds its limit."); return
        }
        buffer.append(bytes)
        guard buffer.count >= 4 else { return }
        let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (24...(WireCodec.maxMessageBytes + 24)).contains(length) else {
            fail("Invalid screen frame size."); return
        }
        guard buffer.count >= length + 4 else { return }
        guard buffer.count == length + 4, completion != nil else { fail("Unexpected screen frame."); return }
        do {
            guard let plain = try cipher?.open(Data(buffer.dropFirst(4))) else {
                throw LinkError.message("Missing screen key.")
            }
            let reply = try JSONDecoder().decode(FastScreenReply.self, from: plain)
            guard let screen = reply.screen, reply.error == nil else {
                throw LinkError.message(reply.error ?? "No screen was returned.")
            }
            try screen.validate()
            buffer.removeAll(keepingCapacity: true); deadline?.cancel()
            let callback = completion; completion = nil; callback?(.success(screen))
        } catch { fail(error.localizedDescription) }
    }
    private func armDeadline() {
        deadline?.cancel()
        let current = generation
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.generation == current else { return }
            self.fail("Bluetooth Classic screen lane timed out.")
        }
    }
    private func fail(_ message: String) {
        let callback = completion
        close()
        callback?(.failure(LinkError.message(message))); onFailure?(message)
    }
    func close() {
        ingress.reset()
        generation = UUID(); deadline?.cancel(); deadline = nil
        completion = nil; ready = false; cipher = nil; buffer.removeAll()
        channel?.setDelegate(nil); channel?.close(); channel = nil; device = nil
    }
    private enum LinkError: LocalizedError {
        case message(String);
        var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
    }
}
