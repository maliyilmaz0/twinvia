import Foundation

/// Reframes variable hardware callbacks into exactly 20 ms of PCM16/16 kHz.
final class PCMFramePacketizer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var dropped = 0
    let frameBytes = 640
    func append(_ data: Data) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        guard data.count % 2 == 0 else { return [] }
        pending.append(data)
        var frames: [Data] = []
        while pending.count >= frameBytes {
            frames.append(Data(pending.prefix(frameBytes))); pending.removeFirst(frameBytes)
        }
        return frames
    }
    func recordDrop() { lock.lock(); dropped += 1; lock.unlock() }
    var droppedFrames: Int { lock.lock(); defer { lock.unlock() }; return dropped }
    var bufferedBytes: Int { lock.lock(); defer { lock.unlock() }; return pending.count }
}

/// Samples not yet consumed by AVAudioPlayerNode, excluding device/DSP latency.
struct AudioPlayoutBudget {
    private(set) var queuedSamples = 0
    private(set) var primed = false
    private(set) var underruns = 0
    private(set) var dropped = 0
    let maxSamples = 12800  // 800 ms upper bound, never an unbounded latency queue.
    private var observedPrimeSamples = 1280
    var primeSamples: Int { max(underruns >= 2 ? 1920 : 1280, observedPrimeSamples) }
    mutating func observeArrivalGap(milliseconds: Double) {
        guard milliseconds.isFinite, milliseconds > 60 else { return }
        // NAN can deliver periodic bursts. Re-prime for the observed gap + 40 ms,
        // capped at 440 ms; normal low-jitter links still start at 80 ms.
        let targetMs = min(440, ceil(milliseconds / 20) * 20 + 40)
        observedPrimeSamples = max(observedPrimeSamples, Int(targetMs) * 16)
    }
    mutating func offer(samples: Int) -> Bool {
        guard samples > 0, queuedSamples + samples <= maxSamples else { dropped += 1; return false }
        queuedSamples += samples; return true
    }
    mutating func startIfReady() -> Bool {
        guard !primed, queuedSamples >= primeSamples else { return false }
        primed = true; return true
    }
    @discardableResult mutating func consumed(samples: Int) -> Bool {
        queuedSamples = max(0, queuedSamples - samples)
        if primed && queuedSamples == 0 { primed = false; underruns += 1; return true }
        return false
    }
}
