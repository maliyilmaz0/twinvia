import TwinviaProtocol
import Combine
import Foundation

@MainActor
final class DeviceControls: ObservableObject {
    @Published private(set) var phone: DeviceStatus?
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    private var pending: (id: String, timeout: Task<Void, Never>)?
    private let send: (DeviceCommand) throws -> String

    init(send: @escaping (DeviceCommand) throws -> String) { self.send = send }

    func receive(_ value: DeviceStatus) { phone = value }
    func receive(_ result: CommandResult) {
        guard pending?.id == result.requestId else { return }
        pending?.timeout.cancel(); pending = nil; busy = false
        message = result.message
    }
    func perform(_ command: DeviceCommand) {
        guard pending == nil else { message = "Waiting for the previous action result."; return }
        do {
            let id = try send(command)
            busy = true
            message = "Waiting for phone result…"
            let task = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(12)) } catch { return }
                guard let self, self.pending?.id == id else { return }
                self.pending = nil; self.busy = false
                self.message = "No result received; check whether the action was applied on your phone."
            }
            pending = (id, task)
        } catch { message = error.localizedDescription }
    }
    func disconnected() {
        phone = nil
        if pending != nil { message = "Disconnected; check the result on your phone." }
        pending?.timeout.cancel(); pending = nil; busy = false
    }
}
