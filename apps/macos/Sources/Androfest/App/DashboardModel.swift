import AndrofestProtocol
import AppKit
import Combine
import Foundation
import UserNotifications
import CryptoKit

@MainActor
final class DashboardModel: ObservableObject {
    let deviceID: String
    let deviceName = Host.current().localizedName ?? "Mac"
    let bridge: BridgeClient
    let transfers: FileTransferController
    let controls: DeviceControls
    let clipboard: AutomaticClipboard
    let phoneData: PhoneDataStore
    let callAudio: CallAudioRelay
    let calls = HandsFreeController()
    private let notificationPresenter = NotificationPresenter()
    @Published private(set) var recentNotifications: [NotificationPosted] = []
    @Published private(set) var files: [LocalFile] = []
    @Published private(set) var notice: String?
    @Published private(set) var isInspecting = false
    @Published private(set) var notificationStatus = "Checking"
    @Published private(set) var mutedApplications: [String: String] = [:]
    @Published private(set) var phoneCall: PhoneCallState?
    private var callHandoff = CallHandoffDecisions()
    private var outgoingAudioUntil: Date?
    @Published var dialNumber = ""
    @Published var dashboardSection = 0

    init() {
        // Preferences migrate only at the composition root, never inside isolated session tests.
        if let address = UserDefaults.standard.string(forKey: "bluetoothPeerAddress") {
            UserDefaults.standard.set(address, forKey: "callBluetoothPeerAddress")
        }
        UserDefaults.standard.removeObject(forKey: "bluetoothPeerAddress")
        UserDefaults.standard.set("ble", forKey: "connectionMode")
        if let saved = UserDefaults.standard.string(forKey: "localDeviceID"), UUID(uuidString: saved) != nil {
            deviceID = saved
        } else {
            deviceID = UUID().uuidString.lowercased()
            UserDefaults.standard.set(deviceID, forKey: "localDeviceID")
        }
        let client = BridgeClient(deviceID: deviceID, name: deviceName)
        bridge = client
        callAudio = CallAudioRelay(
            available: { [weak client] in
                client?.connected == true && client?.peerCapabilities.contains("call.audio") == true
            },
            command: { [weak client] command in
                guard let client else { throw TransferFailure("Phone disconnected") };
                return try client.sendCommand(command)
            },
            sendPCM: { [weak client] bytes in
                guard let client else { throw TransferFailure("Phone disconnected") };
                try await client.sendCallAudio(bytes)
            })
        callAudio.onRealtimeAudio = { [weak client] enabled in client?.setRealtimeAudio(enabled) }
        controls = DeviceControls { [weak client] command in
            guard let client else { throw TransferFailure("Phone disconnected.") }
            return try client.sendCommand(command)
        }
        phoneData = PhoneDataStore(
            available: { [weak client] in
                client?.connected == true && client?.peerCapabilities.contains("phone.browse") == true
            },
            send: { [weak client] command in
                guard let client else { throw TransferFailure("Phone disconnected.") }
                return try client.sendCommand(command)
            })
        clipboard = AutomaticClipboard(
            enabled: UserDefaults.standard.object(forKey: "automaticClipboard") as? Bool ?? true,
            canSend: { [weak client] in
                client?.connected == true && client?.peerCapabilities.contains("clipboard.sync") == true
            },
            saveEnabled: { UserDefaults.standard.set($0, forKey: "automaticClipboard") },
            sendImage: { [weak client] png, id in
                guard let client else { throw TransferFailure("Phone disconnected.") }
                try await client.sendClipboardImage(png, id: id)
            },
            send: { [weak client] text in
                guard let client else { throw TransferFailure("Phone disconnected.") }
                return try client.sendCommand(DeviceCommand(action: .clipboardSet, text: text))
            })
        transfers = FileTransferController(
            send: { [weak client] value in
                guard let client else { throw TransferFailure("Phone disconnected.") }
                try client.sendFileControl(value)
            },
            sendChunk: { [weak client] chunk in
                guard let client else { throw TransferFailure("Phone disconnected.") }
                try client.sendFileChunk(chunk)
            })
        bridge.onConnected = { [weak self] in
            guard let self, self.bridge.peerCapabilities.contains("phone.browse") else { return }
            self.phoneData.load(.contacts); self.phoneData.load(.calls); self.phoneData.load(.files)
        }
        bridge.onCallAudio = { [weak self] in self?.callAudio.receive($0) }
        bridge.onFileControl = { [weak self] in self?.transfers.receive($0) }
        bridge.onFileChunk = { [weak self] in self?.transfers.receiveChunk($0) }
        bridge.onDisconnected = { [weak self] in
            self?.transfers.disconnected(); self?.controls.disconnected(); self?.phoneData.disconnected();
            self?.clipboard.disconnected(); self?.callAudio.disconnected(); self?.phoneCall = nil;
            self?.callHandoff.disconnected(); self?.notificationPresenter.removeIncomingCall()
        }
        bridge.onDeviceStatus = { [weak self] in
            self?.controls.receive($0); self?.receiveCallState($0.call)
        }
        bridge.onSharedText = { [weak self] in self?.clipboard.receive($0.text) }
        bridge.onCommandResult = { [weak self] in
            self?.controls.receive($0); self?.clipboard.receive($0); self?.phoneData.receive($0);
            self?.callAudio.receive($0)
        }
        notificationPresenter.onAction = { [weak self] in self?.controls.perform($0) }
        calls.onIncoming = { [weak self] id in
            guard let self, !self.bridge.peerCapabilities.contains("call.handoff") else { return }
            Task {
                guard self.calls.incomingID == id else { return }
                await self.notificationPresenter.postIncomingCall(id: id, phone: self.calls.phoneName)
            }
        }
        calls.onIncomingEnded = { [weak self] in
            guard self?.bridge.peerCapabilities.contains("call.handoff") != true else { return }
            self?.notificationPresenter.removeIncomingCall()
        }
        notificationPresenter.onCallAction = { [weak self] action, token in
            guard let self else { return }
            if action == UNNotificationDefaultActionIdentifier || action == "answer-call" {
                self.dashboardSection = 2; DashboardWindow.show(model: self)
            }
            if action == "answer-call" {
                self.answerCallOnMac(token: token)
            } else if action == "decline-call" {
                self.endCurrentCall(token: token)
            }
        }
        mutedApplications =
            UserDefaults.standard.dictionary(forKey: "mutedNotificationApplications") as? [String: String] ?? [:]
        notificationPresenter.mutedPackages = Set(mutedApplications.keys)
        notificationPresenter.onError = { [weak self] in self?.notice = $0 }
        notificationPresenter.onSent = { [weak self] in
            if self?.notice?.hasPrefix("Mac notifications") == true { self?.notice = nil }
        }
        bridge.onNotification = { [weak self] message in
            guard let self else { return }
            guard self.mutedApplications[message.payload.packageName] == nil else { return }
            self.recentNotifications.removeAll { $0.key == message.payload.key }
            self.recentNotifications.insert(message.payload, at: 0)
            self.recentNotifications = Array(self.recentNotifications.prefix(30))
            self.notificationPresenter.enqueue(message.payload)
        }
        bridge.onNotificationRemoved = { [weak self] key in
            self?.recentNotifications.removeAll { $0.key == key }
            self?.notificationPresenter.remove(key)
        }
        if let address = UserDefaults.standard.string(forKey: "callBluetoothPeerAddress") {
            Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self,
                    NSRunningApplication.runningApplications(withBundleIdentifier: "dev.androfest.call-lab").isEmpty
                else { return }
                self.calls.connect(address: address)
            }
        }
    }

    private func receiveCallState(_ call: PhoneCallState?) {
        phoneCall = call
        let decision = callHandoff.update(call)
        if decision.dismiss { notificationPresenter.removeIncomingCall() }
        if decision.stopAudio, callAudio.active || callAudio.busy { callAudio.stop(notify: false) }
        guard let call else { return }
        if decision.alert, let token = call.token, let id = UUID(uuidString: token) {
            Task { @MainActor [weak self] in
                guard let self, self.phoneCall?.token == token, self.phoneCall?.state == "ringing" else { return }
                await self.notificationPresenter.postIncomingCall(id: id, phone: self.bridge.peerName ?? "Phone")
            }
        }
        if decision.startAudio {
            outgoingAudioUntil = nil; callAudio.start()
        } else if call.state == "active", let until = outgoingAudioUntil, until > Date(), let token = call.token {
            outgoingAudioUntil = nil
            controls.perform(DeviceCommand(action: .callHandoffApprove, actionToken: token))
        }
    }

    func answerCallOnMac(token: String? = nil) {
        if let call = phoneCall, call.state == "ringing", let current = call.token {
            guard token == nil || token?.lowercased() == current.lowercased() else { return }
            controls.perform(DeviceCommand(action: .callAnswerMac, actionToken: current))
        } else if calls.canAnswer, token == nil || token == calls.incomingID?.uuidString {
            calls.answerOnPhone()
            Task { @MainActor [weak self] in
                for _ in 0..<16 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let self else { return }
                    if self.calls.callActive { self.callAudio.start(); return }
                }
            }
        }
    }
    func endCurrentCall(token: String? = nil) {
        if let current = phoneCall?.token, phoneCall?.state != "idle" {
            guard token == nil || token?.lowercased() == current.lowercased() else { return }
            controls.perform(DeviceCommand(action: .callEnd, actionToken: current))
        } else if token == nil || token == calls.incomingID?.uuidString {
            calls.endCall()
        }
    }
    func dialFromMac(_ number: String) {
        guard calls.connected, !calls.callActive, calls.callSetup == 0, calls.callHeld == 0 else { return }
        outgoingAudioUntil = Date().addingTimeInterval(60)
        calls.dial(number)
    }

    func forgetPhone() { calls.stop(); bridge.forget(); recentNotifications = [] }

    func systemWillSleep() {
        // Audio hardware and the legacy HFP parser must not retain half-open
        // streams across sleep. Native discovery has its own wake recovery.
        callAudio.prepareForSleep()
        calls.prepareForSleep()
    }

    func systemDidWake() {
        calls.resumeAfterWake()
    }

    func applicationWillTerminate() {
        callAudio.stop(notify: false)
        calls.stop()
        bridge.shutdown()
    }

    func connectCalls() {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.androfest.call-lab").isEmpty else {
            calls.connect(address: UserDefaults.standard.string(forKey: "callBluetoothPeerAddress"))
            return
        }
        notice = "Close the separate call test app before connecting the call service."
    }

    func handleURL(_ url: URL) {
        if AppNavigation.handles(url) {
            guard let navigation = AppNavigation(url: url) else { return }
            switch navigation {
            case .calls: dashboardSection = 2
            case .contacts: dashboardSection = 4; phoneData.load(.contacts)
            case .history: dashboardSection = 5; phoneData.load(.calls)
            case .files(let path):
                dashboardSection = 1
                phoneData.load(.files, folder: path)
            }
            return
        }
        if url.isFileURL { selectFiles([url]); return }
        guard let number = CallNumber.from(url) else {
            notice = "This call link does not contain a valid phone number."; return
        }
        dashboardSection = 2
        dialNumber = number
        notice = "Number added to Calls; confirm it before dialing."
    }

    func muteApplication(_ notification: NotificationPosted) {
        mutedApplications[notification.packageName] = notification.appName
        notificationPresenter.mutedPackages = Set(mutedApplications.keys)
        UserDefaults.standard.set(mutedApplications, forKey: "mutedNotificationApplications")
        recentNotifications.removeAll { $0.packageName == notification.packageName }
        Task { await notificationPresenter.removePackage(notification.packageName) }
    }

    func unmuteApplication(_ packageName: String) {
        mutedApplications.removeValue(forKey: packageName)
        notificationPresenter.mutedPackages = Set(mutedApplications.keys)
        UserDefaults.standard.set(mutedApplications, forKey: "mutedNotificationApplications")
    }

    func refreshNotificationStatus() async {
        notificationStatus = NotificationAuthorization.label(await NotificationCenterSnapshot.authorizationStatus())
    }

    func requestNotificationAccess() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await refreshNotificationStatus()
            if notificationStatus == "Notification permission enabled" { notice = nil }
        } catch {
            notice = "Could not obtain notification permission: \(error.localizedDescription)"
        }
    }

    func checkProtocol() {
        do {
            let hello = DeviceHello(
                name: deviceName, platform: "macos",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                capabilities: [])
            let envelope = WireEnvelope(sourceDeviceId: deviceID, payload: hello)
            let decoded = try WireCodec.decode(DeviceHello.self, from: WireCodec.encode(envelope))
            guard decoded.sourceDeviceId == deviceID else { throw ProtocolError.invalidEnvelope }
            notice = "Local protocol validation passed."
        } catch {
            notice = "Protocol validation failed."
        }
    }

    func selectFiles(_ urls: [URL]) {
        guard !isInspecting else { return }
        let selected = Array(urls.filter { url in !files.contains(where: { $0.url == url }) }.prefix(30 - files.count))
        guard !selected.isEmpty else { return }
        isInspecting = true
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                selected.map { url in Result { try LocalFile.inspect(url) } }
            }.value
            for result in results {
                switch result {
                case .success(let file): files.append(file)
                case .failure(let error): notice = error.localizedDescription
                }
            }
            isInspecting = false
        }
    }

    func clearFiles() { files = [] }
    func showError(_ error: Error) { notice = error.localizedDescription }
}
