#if DEBUG
    import Foundation
    import TwinviaProtocol

    /// Synthetic, opt-in device check. The image is validated in memory and never written to disk.
    @MainActor
    final class RemoteSmokeTest {
        private let send: (DeviceCommand) throws -> String
        private var task: Task<Void, Never>?
        private var pending: (id: String, action: DeviceAction, started: Date)?
        private var screenshotOK = false
        private var homeOK = false
        private var lastMessage = "Waiting for phone-approved session"
        private var screenBytes = 0
        private var screenSeconds = 0.0

        init(send: @escaping (DeviceCommand) throws -> String) { self.send = send }

        func connected() {
            task?.cancel()
            task = Task { @MainActor [weak self] in
                for _ in 0..<60 {
                    guard let self, !Task.isCancelled else { return }
                    if self.screenshotOK && self.homeOK { return }
                    if let pending = self.pending, Date().timeIntervalSince(pending.started) > 90 {
                        self.pending = nil
                        self.lastMessage = "Command timed out"
                        self.write()
                    }
                    if self.pending == nil {
                        let action: DeviceAction = self.screenshotOK ? .remoteHome : .remoteSnapshot
                        do {
                            let id = try self.send(DeviceCommand(action: action))
                            self.pending = (id, action, Date())
                        } catch { self.lastMessage = error.localizedDescription; self.write() }
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }

        func receive(_ result: CommandResult) {
            guard let pending, pending.id == result.requestId else { return }
            self.pending = nil
            lastMessage = result.message
            if result.success && pending.action == .remoteSnapshot, let image = result.screen,
                let jpeg = Data(base64Encoded: image.jpegBase64), jpeg.starts(with: [0xFF, 0xD8, 0xFF])
            {
                screenshotOK = true
                screenBytes = jpeg.count
                screenSeconds = Date().timeIntervalSince(pending.started)
            }
            if result.success && pending.action == .remoteHome { homeOK = true }
            write()
        }

        func disconnected() {
            task?.cancel(); task = nil; pending = nil
        }

        private func write() {
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.androfest.macos")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data: [String: Any] = [
                "screenshot": screenshotOK, "home": homeOK, "screenshotBytes": screenBytes,
                "screenshotSeconds": screenSeconds, "message": lastMessage,
            ]
            if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]) {
                try? encoded.write(to: directory.appendingPathComponent("remote-smoke.json"), options: .atomic)
            }
        }
    }
#endif
