import Foundation
import XCTest
@testable import Androfest

final class AudioBufferingTests: XCTestCase {
    func testVariableMicCallbacksProduceExactTwentyMillisecondFramesWithoutLosingSamples() {
        let packetizer = PCMFramePacketizer()
        let input = Data((0..<12_800).map { UInt8(truncatingIfNeeded: $0) })
        var frames: [Data] = []
        var offset = 0
        for size in [340, 684, 1024, 2048, 280, 1920, 6504] {
            frames += packetizer.append(input.subdata(in: offset..<(offset + size))); offset += size
            XCTAssertLessThan(packetizer.bufferedBytes, 640)
        }
        XCTAssertEqual(offset, input.count); XCTAssertEqual(frames.count, 20)
        XCTAssertTrue(frames.allSatisfy { $0.count == 640 })
        XCTAssertEqual(frames.reduce(into: Data()) { $0.append($1) }, input)
    }
    func testPlayoutPrimesAndAcceptsBurstBeyondOldEightPacketLimit() {
        var queue = AudioPlayoutBudget()
        for _ in 0..<3 { XCTAssertTrue(queue.offer(samples: 320)); XCTAssertFalse(queue.startIfReady()) }
        XCTAssertTrue(queue.offer(samples: 320)); XCTAssertTrue(queue.startIfReady())
        for _ in 0..<12 { XCTAssertTrue(queue.offer(samples: 320)) }
        XCTAssertEqual(queue.dropped, 0)
        for _ in 0..<16 { queue.consumed(samples: 320) }
        XCTAssertFalse(queue.primed); XCTAssertEqual(queue.underruns, 1)
        for _ in 0..<4 { XCTAssertTrue(queue.offer(samples: 320)) }
        XCTAssertTrue(queue.startIfReady())
    }
    func testPlayoutLatencyIsBoundedAndRebuffersInsteadOfGrowingForever() {
        var queue = AudioPlayoutBudget()
        for _ in 0..<40 { XCTAssertTrue(queue.offer(samples: 320)) }
        XCTAssertFalse(queue.offer(samples: 320)); XCTAssertEqual(queue.dropped, 1)
        XCTAssertEqual(queue.queuedSamples, 12800)
        XCTAssertTrue(queue.startIfReady())
        queue.consumed(samples: 12800)
        XCTAssertFalse(queue.startIfReady())
    }
    func testNANArrivalGapRaisesRebufferTargetWithinLatencyBound() {
        var queue = AudioPlayoutBudget()
        queue.observeArrivalGap(milliseconds: 340)
        XCTAssertEqual(queue.primeSamples, 6080)  // 380 ms
        for _ in 0..<18 { XCTAssertTrue(queue.offer(samples: 320)); XCTAssertFalse(queue.startIfReady()) }
        XCTAssertTrue(queue.offer(samples: 320)); XCTAssertTrue(queue.startIfReady())
        queue.observeArrivalGap(milliseconds: 10_000)
        XCTAssertEqual(queue.primeSamples, 7040)  // 440 ms cap
    }
}
