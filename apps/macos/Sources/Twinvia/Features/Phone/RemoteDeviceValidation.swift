#if DEBUG
    import Foundation

    /// Explicit CLI-only integration check. It records timings and booleans, never images or keys.
    @MainActor
    final class RemoteDeviceValidation {
        private let remote: RemoteControlModel
        private let privacy: PrivacyBreak
        private let clipboard: AutomaticClipboard
        private let address: String?
        private var task: Task<Void, Never>?
        private var running = false
        private var triggerTask: Task<Void, Never>?
        private var report: [String: Any] = [:]
        init(remote: RemoteControlModel, privacy: PrivacyBreak, clipboard: AutomaticClipboard, address: String?) {
            self.remote = remote; self.privacy = privacy; self.clipboard = clipboard; self.address = address
            triggerTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                    guard let self else { return }
                    let file = self.folder.appendingPathComponent("remote-validation-request")
                    if let handle = try? FileHandle(forReadingFrom: file) {
                        let command = try? handle.read(upToCount: 4)
                        try? handle.close()
                        if command == Data("run".utf8) {
                            try? FileManager.default.removeItem(at: file)
                            self.connected()
                        }
                    }
                }
            }
        }
        func connected() {
            guard !running else { return }
            running = true; report = [:]
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                defer { self.running = false }
                do {
                    self.remote.configure(supportsDetail: true, supportsLAN: self.remote.lanAvailable)
                    self.report["phase"] = "Approve screen viewing on the phone"; self.write()
                    var first = false
                    for _ in 0..<40 {
                        let sequence = self.remote.frameSequence
                        self.remote.quality = .responsive; self.remote.requestFrame()
                        if await self.wait(
                            seconds: 20, until: { !self.remote.busy && self.remote.frameSequence > sequence })
                        {
                            first = true; break
                        }
                        try await Task.sleep(for: .seconds(2))
                    }
                    guard first else { throw Failure.message("No phone-approved screen received") }
                    self.recordFrame("bleResponsive")
                    let sequence = self.remote.frameSequence
                    self.remote.quality = .detail; self.remote.requestFrame()
                    guard
                        await self.wait(
                            seconds: 60, until: { !self.remote.busy && self.remote.frameSequence > sequence })
                    else {
                        throw Failure.message("BLE detail response did not complete")
                    }
                    self.recordFrame("bleDetail")
                    self.report["phase"] = "Testing Wi-Fi screen lane"; self.write()
                    self.remote.connectLAN()
                    if await self.wait(seconds: 35, until: { self.remote.fastConnected }) {
                        self.recordFrame("lanDetail")
                        let sequence = self.remote.frameSequence
                        if await self.wait(seconds: 15, until: { self.remote.frameSequence >= sequence + 3 }) {
                            self.recordFrame("lanRepeat")
                        }
                    } else {
                        self.report["lanError"] = self.remote.message
                    }
                    self.remote.setPreview(false)
                    if CommandLine.arguments.contains("--also-classic-validation"), let address = self.address {
                        self.report["phase"] = "Testing optional Classic lane"; self.write()
                        self.remote.connectFast(address: address)
                        if await self.wait(seconds: 35, until: { self.remote.fastConnected }) {
                            self.recordFrame("classicDetail")
                            let sequence = self.remote.frameSequence
                            if await self.wait(seconds: 20, until: { self.remote.frameSequence >= sequence + 2 }) {
                                self.recordFrame("classicRepeat")
                            }
                        } else {
                            self.report["classicError"] = self.remote.message
                        }
                        self.remote.setPreview(false)
                    }
                    self.privacy.start(.five)
                    self.report["privacyClearsScreen"] = self.remote.image == nil && self.clipboard.paused
                    self.remote.requestFrame()
                    self.report["privacyRejectsRemoteRequest"] = !self.remote.busy && self.remote.image == nil
                    self.privacy.resume()
                    self.report["privacyResumesClipboard"] = !self.clipboard.paused
                    if CommandLine.arguments.contains("--remote-scroll-validation") {
                        self.remote.scroll(.down)
                        _ = await self.wait(seconds: 15, until: { !self.remote.busy })
                        self.report["scrollResult"] = self.remote.message
                    }
                    self.report["phase"] = "Complete"; self.write()
                } catch {
                    self.report["phase"] = "Stopped"; self.report["error"] = error.localizedDescription; self.write()
                }
            }
        }
        private func wait(seconds: Double, until condition: () -> Bool) async -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end, !Task.isCancelled {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(200))
            }
            return false
        }
        private func recordFrame(_ key: String) {
            if let metrics = remote.frameMetrics, let data = try? JSONEncoder().encode(metrics),
                let object = try? JSONSerialization.jsonObject(with: data)
            {
                report[key] = object
            }
            report["phase"] = key; write()
        }
        private var folder: URL {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(
                "dev.androfest.macos")
        }
        private func write() {
            report["updatedAt"] = Date().ISO8601Format()
            let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.androfest.macos")
            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                try? data.write(to: folder.appendingPathComponent("remote-device-validation.json"), options: .atomic)
            }
        }
        private enum Failure: LocalizedError {
            case message(String)
            var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
        }
    }
#endif
