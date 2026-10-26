import TwinviaProtocol
import Foundation
import XCTest
@testable import Twinvia

@MainActor
final class PeerLinkLifecycleTests: XCTestCase {
    private final class FakeLink: PeerLink {
        var onStatus: ((String) -> Void)?
        var onIntroduction: ((PairingIntroduction) -> Bool)?
        var onReady: ((UInt16, PairingIntroduction) -> Void)?
        var onClosed: (() -> Void)?
        var diagnosticState = "test"
        var isRunning = false
        var starts = 0
        var stops = 0
        func start(invitation: PairingInvitation) { starts += 1; isRunning = true }
        func retryEndpoint() {}
        func setRealtimeAudio(_ enabled: Bool) {}
        func stop() { stops += 1; isRunning = false }
    }

    func testStartupIsIdempotentAndShutdownStopsTransport() {
        let link = FakeLink()
        let client = BridgeClient(
            deviceID: UUID().uuidString.lowercased(), name: "Test", persist: false,
            makeLink: { link }, linkAvailable: { true })
        XCTAssertNotNil(client.invitation)
        client.connectPeer()
        XCTAssertEqual(link.starts, 1)
        client.shutdown()
        XCTAssertEqual(link.stops, 1)
        XCTAssertFalse(client.connected)
    }

    func testUnavailableHelperDoesNotDiscardInvitation() {
        var created = false
        let client = BridgeClient(
            deviceID: UUID().uuidString.lowercased(), name: "Test", persist: false,
            makeLink: {
                created = true; return FakeLink()
            }, linkAvailable: { false })
        XCTAssertNotNil(client.invitation)
        XCTAssertFalse(created)
        XCTAssertFalse(client.connected)
        client.shutdown()
    }

    func testLateTrustReadCannotRestartTransportAfterShutdown() async throws {
        var created = false
        let client = BridgeClient(
            deviceID: UUID().uuidString.lowercased(), name: "Test",
            loadTrust: { _, _ in
                Thread.sleep(forTimeInterval: 0.1); return nil
            },
            makeLink: {
                created = true; return FakeLink()
            }, linkAvailable: { true })
        client.shutdown()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(created)
        XCTAssertNil(client.invitation)
    }
}
