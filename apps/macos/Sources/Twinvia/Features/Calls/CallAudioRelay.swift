import AVFoundation
import TwinviaProtocol
import Combine
import Foundation

/// Explicit, experimental PCM call relay. No audio is stored on disk.
@MainActor
final class CallAudioRelay: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Mac audio relay ready for testing"
    private var engine: AVAudioEngine?
    private var tapInstalled = false
    private var player: AVAudioPlayerNode?
    private var id: UUID?
    private var startRequest: String?
    private var sender: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var playbackQueued = 0  // Local diagnostic only.
    private var playout = AudioPlayoutBudget()
    private var capturePacketizer = PCMFramePacketizer()
    private var downlinkOffered = 0
    private var lastArrival: TimeInterval?
    private var maxArrivalGapMs = 0.0
    private var playbackCompleted = 0
    private var localFormatsMatch = false
    private var captured = 0
    private var localInputFormat = ""
    private var localOutputFormat = ""
    private var received = 0
    private var sent = 0
    private let command: (DeviceCommand) throws -> String
    private let sendPCM: (Data) async throws -> Void
    private let available: () -> Bool
    var onRealtimeAudio: ((Bool) -> Void)?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!

    init(
        available: @escaping () -> Bool, command: @escaping (DeviceCommand) throws -> String,
        sendPCM: @escaping (Data) async throws -> Void
    ) {
        self.available = available; self.command = command; self.sendPCM = sendPCM
    }
    func start() {
        guard id == nil, !busy, !active, available() else { return }
        busy = true; status = "Mikrofon izni kontrol ediliyor"
        let token = UUID(); id = token
        Task { @MainActor [weak self] in
            let permission = await AVCaptureDevice.requestAccess(for: .audio)
            guard let self, self.id == token else { return }
            guard permission else {
                self.stop(notify: false);
                self.status = "Allow Twinvia in System Settings → Privacy & Security → Microphone"; return
            }
            do {
                try self.prepare(token: token)
                self.onRealtimeAudio?(true)
                self.startRequest = try self.command(
                    DeviceCommand(action: .callAudioStart, actionToken: token.uuidString.lowercased()))
                self.status = "Opening phone call audio channel"
                self.deadline = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(8)) } catch { return }
                    guard let self, self.busy else { return }
                    self.stop(); self.status = "Audio helper did not respond; check USB activation"
                }
            } catch { self.stop(); self.status = "Could not open audio channel: \(error.localizedDescription)" }
        }
    }
    private func prepare(token: UUID) throws {
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        self.engine = engine; self.player = player
        let input = engine.inputNode
        // System voice processing provides echo cancellation for the local mic/speakers.
        try input.setVoiceProcessingEnabled(true)
        let deviceFormat = input.outputFormat(forBus: 0)
        guard let hardware = AVAudioFormat(standardFormatWithSampleRate: deviceFormat.sampleRate, channels: 1) else {
            throw TransferFailure("Mac audio format unavailable")
        }
        // VPIO requires exactly matching client formats on input and output.
        // Keep hardware I/O at the capture format; the mixer converts 16 kHz phone PCM.
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: hardware)

        guard hardware.sampleRate > 0, hardware.channelCount > 0,
            let converter = AVAudioConverter(from: hardware, to: format)
        else { throw TransferFailure("Mac microphone format is not supported") }
        capturePacketizer = PCMFramePacketizer(); playout = AudioPlayoutBudget()
        lastArrival = nil; maxArrivalGapMs = 0
        let (stream, continuation) = AsyncStream<Data>.makeStream(bufferingPolicy: .bufferingNewest(16))
        input.installTap(
            onBus: 0, bufferSize: AVAudioFrameCount(hardware.sampleRate / 50), format: hardware,
            block: Self.makeCaptureTap(
                converter: converter, sampleRate: hardware.sampleRate, token: token, continuation: continuation,
                packetizer: capturePacketizer))
        tapInstalled = true
        let inputFormat = input.outputFormat(forBus: 0), outputFormat = engine.outputNode.inputFormat(forBus: 0)
        localFormatsMatch = inputFormat.isEqual(outputFormat)
        localInputFormat =
            "\(inputFormat.sampleRate) Hz / \(inputFormat.channelCount) ch / \(inputFormat.commonFormat.rawValue)"
        localOutputFormat =
            "\(outputFormat.sampleRate) Hz / \(outputFormat.channelCount) ch / \(outputFormat.commonFormat.rawValue)"
        sender = Task { @MainActor [weak self] in
            for await frame in stream {
                guard !Task.isCancelled, let self, self.id == token else { break }
                self.captured += 1
                guard self.active else { continue }
                do { try await self.sendPCM(frame); self.sent += 1 } catch {
                    self.stop(notify: false); self.status = "Audio connection lost"; break
                }
            }
        }
        try engine.start()  // Start output only after the jitter buffer is primed.
    }
    private nonisolated static func makeCaptureTap(
        converter: AVAudioConverter, sampleRate: Double, token: UUID,
        continuation: AsyncStream<Data>.Continuation, packetizer: PCMFramePacketizer
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            guard
                let converted = AVAudioPCMBuffer(
                    pcmFormat: converter.outputFormat,
                    frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / sampleRate + 32))
            else { return }
            var provided = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, flag in
                if provided { flag.pointee = .noDataNow; return nil }
                provided = true; flag.pointee = .haveData; return buffer
            }
            guard error == nil, let samples = converted.floatChannelData?[0] else { return }
            var pcm = Data(capacity: Int(converted.frameLength) * 2)
            for index in 0..<Int(converted.frameLength) {
                let sample = samples[index].isFinite ? max(-1, min(1, samples[index])) : 0
                var value = Int16(sample * 32767).littleEndian
                withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
            }
            for payload in packetizer.append(pcm) {
                var frame = Data("AAP1".utf8), uuid = token.uuid
                withUnsafeBytes(of: &uuid) { frame.append(contentsOf: $0) }
                frame.append(payload)
                if case .dropped = continuation.yield(frame) { packetizer.recordDrop() }
            }
        }
    }

    private nonisolated static func playedBack(owner: CallAudioRelay, token: UUID, samples: Int = 0)
        -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void
    {
        return { [weak owner] _ in
            Task { @MainActor in
                guard let owner, owner.id == token else { return }
                if samples > 0 {
                    if owner.playout.consumed(samples: samples) { owner.player?.pause() }
                } else {
                    owner.playbackQueued = max(0, owner.playbackQueued - 1)
                }
                owner.playbackCompleted += 1
            }
        }
    }

    #if DEBUG
        func selfTestLocalEngine() {
            guard id == nil else { return }
            let token = UUID(); id = token
            Task { @MainActor [weak self] in
                guard let self, await AVCaptureDevice.requestAccess(for: .audio), self.id == token else { return }
                var result: [String: Any] = [:]
                do {
                    let baseline = self.captured
                    try self.prepare(token: token)
                    let playedBaseline = self.playbackCompleted
                    if let silence = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: 320) {
                        silence.frameLength = 320
                        silence.floatChannelData?[0].update(repeating: 0, count: 320)
                        self.playbackQueued += 1
                        self.player?.scheduleBuffer(
                            silence, completionCallbackType: .dataPlayedBack,
                            completionHandler: Self.playedBack(owner: self, token: token))
                        self.player?.play()
                    }
                    try await Task.sleep(for: .seconds(2))
                    result = [
                        "engineRunning": self.engine?.isRunning == true,
                        "formatsMatch": self.localFormatsMatch,
                        "silentPlaybackCompleted": self.playbackCompleted > playedBaseline,
                        "inputFormat": self.localInputFormat, "outputFormat": self.localOutputFormat,
                        "capturedPackets": self.captured - baseline, "remoteAudioRequested": false,
                    ]
                    self.stop(notify: false)
                    self.status = "Mac audio engine checked · Waiting for call approval"
                } catch {
                    self.stop(notify: false)
                    self.status = "Mac audio engine test failed: \(error.localizedDescription)"
                    result = [
                        "engineRunning": false, "error": error.localizedDescription, "remoteAudioRequested": false,
                    ]
                }
                self.diagnostics()
                let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("dev.androfest.macos")
                if let data = try? JSONSerialization.data(withJSONObject: result) {
                    try? data.write(
                        to: directory.appendingPathComponent("call-audio-engine-test.json"), options: .atomic)
                }
            }
        }
    #endif

    func receive(_ result: CommandResult) {
        if result.requestId == startRequest {
            deadline?.cancel(); deadline = nil; startRequest = nil
            if result.success {
                active = true; busy = false; status = "Mac audio bridge active · Verify two-way audio"
            } else {
                stop(notify: false); status = result.message
            }
        } else if result.requestId == id?.uuidString.lowercased(), !result.success {
            stop(notify: false); status = result.message
        }
        diagnostics()
    }
    func receive(_ frame: Data) {
        guard active || busy, let id, frame.count >= 22, frame.count <= 1940, (frame.count - 20) % 2 == 0,
            frame.prefix(4) == Data("AAP1".utf8)
        else { return }
        var expected = id.uuid
        guard withUnsafeBytes(of: &expected, { Data($0) }) == frame.subdata(in: 4..<20),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount((frame.count - 20) / 2)),
            let samples = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = buffer.frameCapacity
        let bytes = Array(frame.dropFirst(20))
        for i in 0..<Int(buffer.frameLength) {
            samples[i] = Float(Int16(bitPattern: UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8)) / 32768
        }
        downlinkOffered += 1
        let now = ProcessInfo.processInfo.systemUptime
        if let lastArrival {
            let gap = (now - lastArrival) * 1000
            maxArrivalGapMs = max(maxArrivalGapMs, gap)
            playout.observeArrivalGap(milliseconds: gap)
        }
        lastArrival = now
        guard playout.offer(samples: Int(buffer.frameLength)) else { return }
        received += 1
        // dataConsumed tracks queued audio, not the additional hardware/voice-DSP delay.
        player?.scheduleBuffer(
            buffer, completionCallbackType: .dataConsumed,
            completionHandler: Self.playedBack(owner: self, token: id, samples: Int(buffer.frameLength)))
        if playout.startIfReady() { player?.play() }
        if received % 50 == 0 { diagnostics() }
    }
    func disconnected() {
        // A local engine diagnostic has no remote session to interrupt.
        if active || busy { stop(notify: false) }
    }
    func prepareForSleep() {
        guard id != nil || engine != nil else { return }
        stop(notify: false)
        status = "Mac sleeping · Call audio remains on the phone"
    }
    func stop(notify: Bool = true) {
        onRealtimeAudio?(false)
        let old = id; id = nil; active = false; busy = false; startRequest = nil
        deadline?.cancel(); deadline = nil; sender?.cancel(); sender = nil
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine?.stop(); player?.stop(); engine = nil; player = nil
        playbackQueued = 0; lastArrival = nil; status = "Call audio remains on the phone"
        if notify, let old {
            _ = try? command(DeviceCommand(action: .callAudioStop, actionToken: old.uuidString.lowercased()))
        }
        diagnostics()
    }
    private func diagnostics() {
        #if DEBUG
            let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dev.androfest.macos")
            if let data = try? JSONSerialization.data(withJSONObject: [
                "active": active, "busy": busy, "downlinkPackets": received, "uplinkPackets": sent,
                "capturedPackets": captured, "captureQueueDrops": capturePacketizer.droppedFrames,
                "downlinkOffered": downlinkOffered, "playbackDrops": playout.dropped,
                "playbackUnderruns": playout.underruns, "maxArrivalGapMs": maxArrivalGapMs,
                "playbackQueuedMs": playout.queuedSamples / 16, "playbackTargetMs": playout.primeSamples / 16,
                "inputFormat": localInputFormat, "outputFormat": localOutputFormat, "status": status,
            ]) {
                try? data.write(to: directory.appendingPathComponent("call-audio-status.json"), options: .atomic)
            }
        #endif
    }
}
