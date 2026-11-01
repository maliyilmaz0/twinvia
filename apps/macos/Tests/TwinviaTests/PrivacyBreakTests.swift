import XCTest
@testable import Twinvia

@MainActor
final class PrivacyBreakTests: XCTestCase {
    func testPausePersistsOnlyDeadlineAndExpiresAfterWakeWithoutReplaying() {
        var now = Date(timeIntervalSince1970: 1000)
        var saved: Date?
        var states: [Bool] = []
        let privacy = PrivacyBreak(now: { now }, scheduleExpiry: false, save: { saved = $0 })
        privacy.onChange = { states.append($0) }
        privacy.start(.five)
        XCTAssertTrue(privacy.active)
        XCTAssertEqual(saved, now.addingTimeInterval(300))
        now = now.addingTimeInterval(301)
        privacy.refresh(); privacy.refresh()
        XCTAssertFalse(privacy.active); XCTAssertNil(saved)
        XCTAssertEqual(states, [true, false])
    }
    func testRestartRestoresOnlyUnexpiredBoundedBreaksAndResumeIsIdempotent() {
        let now = Date(timeIntervalSince1970: 1000)
        let restored = PrivacyBreak(savedUntil: now.addingTimeInterval(600), now: { now }, scheduleExpiry: false)
        XCTAssertTrue(restored.active)
        restored.resume(); restored.resume(); XCTAssertFalse(restored.active)
        XCTAssertFalse(PrivacyBreak(savedUntil: now.addingTimeInterval(-1), now: { now }, scheduleExpiry: false).active)
        XCTAssertFalse(
            PrivacyBreak(savedUntil: now.addingTimeInterval(3601), now: { now }, scheduleExpiry: false).active)
    }
}
