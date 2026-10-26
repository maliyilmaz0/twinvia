import CryptoKit
import Foundation
import Security
import XCTest
@testable import Androfest

final class CertificatePinningTests: XCTestCase {
    private func certificateData() throws -> Data {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tls-test.der")
        return try Data(contentsOf: file)
    }

    func testMatchingPinAcceptedOnBackgroundExecutor() async throws {
        let data = try certificateData()
        let result = try await Task.detached {
            let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
            var trust: SecTrust?
            XCTAssertEqual(
                SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust), errSecSuccess)
            let reference = try XCTUnwrap(trust)
            // Keep the fixed public fixture test independent from the machine's current date.
            SecTrustSetVerifyDate(reference, Date(timeIntervalSince1970: 1792200000) as CFDate)
            let pin = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return CertificatePinning.verify(reference, fingerprint: pin)
        }.value
        XCTAssertTrue(result)
    }

    func testDifferentPinRejectedEvenForExplicitTrustAnchor() async throws {
        let data = try certificateData()
        let result = try await Task.detached {
            let certificate = try XCTUnwrap(SecCertificateCreateWithData(nil, data as CFData))
            var trust: SecTrust?
            XCTAssertEqual(
                SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust), errSecSuccess)
            let reference = try XCTUnwrap(trust)
            SecTrustSetAnchorCertificates(reference, [certificate] as CFArray)
            return CertificatePinning.verify(reference, fingerprint: String(repeating: "0", count: 64))
        }.value
        XCTAssertFalse(result)
    }
}
