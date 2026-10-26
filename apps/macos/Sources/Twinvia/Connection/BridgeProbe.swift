#if DEBUG
    import TwinviaProtocol
    import Foundation
    import Darwin

    /// Headless debug harness. The invitation is bootstrapped over an already authorized USB connection.
    enum BridgeProbe {
        @MainActor
        static func run(directory: URL) {
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let client = BridgeClient(
                    deviceID: UUID().uuidString.lowercased(), name: "Twinvia connection test", persist: false)
                var confirmed = false
                var systemConfirmed = false
                client.onNotification = { message in
                    if message.payload.packageName == "dev.androfest.android"
                        && message.payload.key == "androfest-connection-test"
                    {
                        confirmed = true
                    }
                    if message.payload.packageName == "dev.androfest.android"
                        && message.payload.title == "Twinvia ready"
                    {
                        systemConfirmed = true
                    }
                }
                Task { @MainActor in
                    let deadline = Date().addingTimeInterval(180)
                    var exported = false
                    while Date() < deadline {
                        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("STOP").path) {
                            exit(0)
                        }
                        if !exported, let invitation = client.invitation, let link = try? invitation.link() {
                            let file = directory.appendingPathComponent("invitation.txt")
                            try? Data(link.utf8).write(to: file, options: .atomic)
                            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                            exported = true
                        }
                        let snapshot = ProbeSnapshot(
                            connected: client.connected, receivedCount: client.receivedCount,
                            testConfirmed: confirmed, systemNotificationConfirmed: systemConfirmed,
                            status: client.status, transportStatus: client.transportStatus,
                            transportEvent: client.transportEvent)
                        if let data = try? JSONEncoder().encode(snapshot) {
                            try? data.write(to: directory.appendingPathComponent("status.json"), options: .atomic)
                        }
                        if client.connected {
                            try? FileManager.default.removeItem(at: directory.appendingPathComponent("invitation.txt"))
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    exit(2)
                }
                RunLoop.main.run()
            } catch { exit(1) }
        }

        private struct ProbeSnapshot: Encodable {
            let connected: Bool
            let receivedCount: Int
            let testConfirmed: Bool
            let systemNotificationConfirmed: Bool
            let status: String
            let transportStatus: String
            let transportEvent: String
        }
    }
#endif
