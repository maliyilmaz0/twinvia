import CryptoKit
import Foundation
import Network
import Security

enum CertificatePinning {
    // C callbacks inherit actor isolation from their creation site. Build this callback
    // outside BridgeClient's MainActor: Network invokes it on the queue supplied below.
    nonisolated static func configure(_ options: NWProtocolTLS.Options, fingerprint: String) {
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, trust, completion in
                let reference = sec_trust_copy_ref(trust).takeRetainedValue()
                completion(verify(reference, fingerprint: fingerprint))
            }, DispatchQueue.global(qos: .userInitiated))
    }

    nonisolated static func verify(_ trust: SecTrust, fingerprint: String) -> Bool {
        SecTrustSetNetworkFetchAllowed(trust, false)
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
            let certificate = certificates.first,
            SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map({ String(format: "%02x", $0) }).joined()
                == fingerprint
        else {
            return false
        }
        // The QR secret authenticated this exact leaf. Public system roots cannot replace it.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        let valid = SecTrustEvaluateWithError(trust, &error)
        #if DEBUG
            if !valid { NSLog("Twinvia pinned certificate validation failed: %@", String(describing: error)) }
        #endif
        return valid
    }
}
