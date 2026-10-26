package dev.androfest.android.core.connection

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.security.auth.x500.X500Principal

class TlsIdentity {
    private val alias = "androfest.tls.v2"
    private val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    init {
        if (!store.containsAlias(alias)) {
            val now = System.currentTimeMillis()
            val spec =
                KeyGenParameterSpec.Builder(
                        alias,
                        KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                    )
                    .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
                    // Conscrypt hashes TLS transcripts itself and asks Keystore for raw ECDSA
                    // signing.
                    .setDigests(
                        KeyProperties.DIGEST_NONE,
                        KeyProperties.DIGEST_SHA256,
                        KeyProperties.DIGEST_SHA384,
                        KeyProperties.DIGEST_SHA512,
                    )
                    .setCertificateSubject(X500Principal("CN=Twinvia Android"))
                    .setCertificateSerialNumber(BigInteger(128, SecureRandom()).add(BigInteger.ONE))
                    .setCertificateNotBefore(Date(now - 86_400_000))
                    .setCertificateNotAfter(Date(now + 10L * 365 * 86_400_000))
                    .build()
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
                .apply {
                    initialize(spec)
                }
                .generateKeyPair()
        }
    }

    private val certificate
        get() = store.getCertificate(alias) as X509Certificate

    val fingerprint: String
        get() =
            MessageDigest.getInstance("SHA-256").digest(certificate.encoded).joinToString("") {
                "%02x".format(it)
            }

    fun context(): SSLContext {
        certificate.checkValidity()
        certificate.verify(certificate.publicKey)
        val managers =
            KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply {
                init(store, null)
            }
        return SSLContext.getInstance("TLS").apply {
            init(managers.keyManagers, null, SecureRandom())
        }
    }
}
