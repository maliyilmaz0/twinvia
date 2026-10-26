package dev.twinvia.protocol

import java.net.URI
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString

@Serializable
data class PairingInvitation(
    val version: Int,
    val id: String,
    val deviceId: String,
    val name: String,
    val host: String? = null,
    val port: Int? = null,
    val secret: String,
    val expiresAt: Long,
) {
    fun validate(now: Long = System.currentTimeMillis(), allowExpired: Boolean = false) {
        require(version in 1..2 && validUUID(id) && validUUID(deviceId)) {
            "Invalid pairing code"
        }
        require(name.isNotBlank() && name.length <= 128)
        require(secret.matches(Regex("[a-f0-9]{64}")))
        if (version == 1) {
            require(port != null && port in 1024..65535)
            val address = requireNotNull(host).split('.').map { it.toIntOrNull() }
            require(address.size == 4 && address.all { it != null && it in 0..255 })
            require(
                address[0] == 10 ||
                    (address[0] == 172 && address[1] in 16..31) ||
                    (address[0] == 192 && address[1] == 168)
            )
        } else {
            require(host == null && port == null) {
                "Direct pairing does not contain a network address"
            }
        }
        require(expiresAt > 0)
        if (!allowExpired)
            require(expiresAt > now && expiresAt <= now + 315_000) {
                "QR code expired. Refresh it on Mac."
            }
    }

    companion object {
        fun fromLink(link: String, now: Long = System.currentTimeMillis()): PairingInvitation {
            require(link.length <= 4096)
            val uri = URI(link)
            require(uri.scheme == "androfest" && uri.host == "pair") {
                "This is not a Twinvia QR code"
            }
            val query = uri.rawQuery ?: error("Pairing information is missing")
            require(query.startsWith("data=") && !query.contains('&'))
            val bytes = Base64.getUrlDecoder().decode(query.removePrefix("data="))
            return WireCodec.json
                .decodeFromString<PairingInvitation>(bytes.toString(Charsets.UTF_8))
                .also { it.validate(now) }
        }
    }
}

@Serializable
data class PairingIntroduction(
    val version: Int = 1,
    val invitationId: String,
    val deviceId: String,
    val name: String,
    val port: Int,
    val fingerprint: String,
    val nonce: String,
    val timestamp: Long,
    val proof: String,
) {
    fun authenticatedText(): String =
        listOf(
                "androfest.introduction.v1",
                invitationId,
                deviceId,
                Base64.getUrlEncoder()
                    .withoutPadding()
                    .encodeToString(name.toByteArray(Charsets.UTF_8)),
                port.toString(),
                fingerprint,
                nonce,
                timestamp.toString(),
            )
            .joinToString("\n")

    fun verify(invitation: PairingInvitation, now: Long = System.currentTimeMillis()): Boolean =
        runCatching {
                require(version == 1 && invitationId == invitation.id && validUUID(deviceId))
                require(name.isNotBlank() && name.length <= 128 && port in 1024..65535)
                require(
                    fingerprint.matches(Regex("[a-f0-9]{64}")) &&
                        nonce.matches(Regex("[a-f0-9]{32}"))
                )
                require(timestamp >= now - 90_000 && timestamp <= now + 90_000)
                require(proof.matches(Regex("[a-f0-9]{64}")))
                MessageDigest.isEqual(
                    proof.toByteArray(),
                    hmac(invitation.secret, authenticatedText()).toByteArray(),
                )
            }
            .getOrDefault(false)

    companion object {
        fun create(
            invitation: PairingInvitation,
            deviceId: String,
            name: String,
            port: Int,
            fingerprint: String,
        ): PairingIntroduction {
            val introduction =
                PairingIntroduction(
                    invitationId = invitation.id,
                    deviceId = deviceId,
                    name = name.take(128),
                    port = port,
                    fingerprint = fingerprint,
                    nonce = randomHex(16),
                    timestamp = System.currentTimeMillis(),
                    proof = "",
                )
            return introduction.copy(
                proof = hmac(invitation.secret, introduction.authenticatedText())
            )
        }
    }
}

@Serializable
data class SessionAuthentication(
    val kind: String = "session.auth",
    val version: Int = 1,
    val invitationId: String,
    val deviceId: String,
    val secret: String,
    val capabilities: List<String> = emptyList(),
)

fun randomHex(bytes: Int): String =
    ByteArray(bytes).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }

private fun hmac(secret: String, message: String): String {
    val key = secret.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    return Mac.getInstance("HmacSHA256")
        .apply { init(SecretKeySpec(key, "HmacSHA256")) }
        .doFinal(message.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
}

private fun validUUID(value: String): Boolean =
    runCatching { UUID.fromString(value).toString().equals(value, true) }.getOrDefault(false)
