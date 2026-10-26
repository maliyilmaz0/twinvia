import AndrofestProtocol
import XCTest
@testable import Androfest

final class CallHandoffTests: XCTestCase {
    func testStatusUpdatesAndReconnectNeverRepeatRingingAlert() {
        var state = CallHandoffDecisions()
        let ringing = PhoneCallState(state: "ringing", token: "a")
        XCTAssertTrue(state.update(ringing).alert)
        for _ in 0..<100 { XCTAssertFalse(state.update(ringing).alert) }
        state.disconnected(); XCTAssertFalse(state.update(ringing).alert)
        XCTAssertTrue(state.update(PhoneCallState(state: "active", token: "a")).dismiss)
        XCTAssertFalse(state.update(ringing).alert)
        _ = state.update(PhoneCallState(state: "idle"))
        XCTAssertTrue(state.update(PhoneCallState(state: "ringing", token: "b")).alert)
    }
    func testPhoneAnswerNeedsConsentAndEachApprovalStartsOnlyOnce() {
        var state = CallHandoffDecisions()
        XCTAssertFalse(state.update(PhoneCallState(state: "active", token: "a")).startAudio)
        let approved = PhoneCallState(state: "active", token: "a", approval: "approval-1")
        XCTAssertTrue(state.update(approved).startAudio)
        for _ in 0..<100 { XCTAssertFalse(state.update(approved).startAudio) }
        XCTAssertTrue(state.update(PhoneCallState(state: "active", token: "a")).stopAudio)
        XCTAssertTrue(state.update(PhoneCallState(state: "active", token: "a", approval: "approval-2")).startAudio)
        XCTAssertTrue(state.update(PhoneCallState(state: "idle")).stopAudio)
    }
}
