import Foundation
import XCTest
@testable import Androfest

@MainActor
final class KeychainStartupTests: XCTestCase {
    private enum Denied: Error { case access }
    private final class Attempts: @unchecked Sendable {
        private let lock = NSLock()
        private var flags: [Bool] = []
        func record(_ flag: Bool) { lock.lock(); flags.append(flag); lock.unlock() }
        var values: [Bool] { lock.lock(); defer { lock.unlock() }; return flags }
    }
    func testDeniedStartupNeverCreatesNewPairingAndOnlyExplicitRetryMayPrompt() async throws {
        let attempts = Attempts()
        let client = BridgeClient(
            deviceID: UUID().uuidString.lowercased(), name: "Keychain test",
            loadTrust: { _, interactive in
                attempts.record(interactive); throw Denied.access
            })
        for _ in 0..<100 {
            if client.requiresKeychainAccess { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(client.requiresKeychainAccess)
        XCTAssertNil(client.invitation)
        XCTAssertEqual(attempts.values, [false])
        client.renewInvitation()
        XCTAssertNil(client.invitation)
        client.readSavedTrust()
        for _ in 0..<100 {
            if attempts.values.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(attempts.values, [false, true])
        XCTAssertNil(client.invitation)
    }
}
