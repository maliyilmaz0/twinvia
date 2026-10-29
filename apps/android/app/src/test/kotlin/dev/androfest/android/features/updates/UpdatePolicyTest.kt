package dev.androfest.android.features.updates

import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import org.junit.Assert.*
import org.junit.Test

class UpdatePolicyTest {
    @Test
    fun `only authentic bounded release metadata is accepted`() {
        val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
        val pub = Base64.getEncoder().encodeToString(pair.public.encoded.takeLast(32).toByteArray())
        fun signed(json: String): String {
            val signer = Signature.getInstance("Ed25519")
            signer.initSign(pair.private)
            signer.update("Twinvia Android Update v1\u0000".toByteArray())
            signer.update(json.toByteArray())
            return Base64.getEncoder().encodeToString(signer.sign())
        }
        val payload =
            """{"version":"0.10.0","build":12,"android":{"url":"https://github.com/maliyilmaz0/twinvia/releases/download/v0.10.0/Twinvia.apk","sha256":"${"a".repeat(64)}","size":100}}"""
        assertEquals(12L, UpdatePolicy.verify(payload.toByteArray(), signed(payload), pub).build)
        assertThrows(IllegalArgumentException::class.java) {
            UpdatePolicy.verify(payload.replace("12", "13").toByteArray(), signed(payload), pub)
        }
        for (bad in
            listOf(
                payload.replace("github.com", "example.com"),
                payload.replace("\"size\":100", "\"size\":209715201"),
                payload.replace("/v0.10.0/", "/v0.9.0/"),
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                UpdatePolicy.verify(bad.toByteArray(), signed(bad), pub)
            }
        }
    }
}
