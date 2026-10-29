package dev.twinvia.protocol

import java.nio.ByteBuffer
import java.util.Base64
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.Serializable

@Serializable
data class RemoteChannel(val session: String, val key: String) {
    fun validate() {
        require(
            key.length == 44 &&
                UUID.fromString(session).toString() == session &&
                Base64.getDecoder().decode(key).size == 32
        )
    }

    companion object {
        const val SERVICE_ID = "c6175595-dfce-4e3f-a61b-ec9efb8c9ba2"
    }
}

@Serializable
data class FastScreenReply(val screen: RemoteScreen? = null, val error: String? = null)

class RemoteFrameCipher(channel: RemoteChannel, mac: Boolean) {
    private val key: SecretKeySpec
    private val session = channel.session.toByteArray(Charsets.UTF_8)
    private val sending = (if (mac) "MAC0" else "AND0").toByteArray()
    private val receiving = (if (mac) "AND0" else "MAC0").toByteArray()
    private var sent = 0L
    private var received = 0L

    init {
        channel.validate()
        key = SecretKeySpec(Base64.getDecoder().decode(channel.key), "AES")
    }

    fun seal(plaintext: ByteArray): ByteArray {
        require(plaintext.size <= WireCodec.MAX_MESSAGE_BYTES && sent < Long.MAX_VALUE)
        val count = ByteBuffer.allocate(8).putLong(sent).array()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, sending + count))
        cipher.updateAAD(session + sending + count)
        val result = count + cipher.doFinal(plaintext)
        sent++
        return result
    }

    fun open(bytes: ByteArray): ByteArray {
        require(bytes.size in 24..(WireCodec.MAX_MESSAGE_BYTES + 24) && received < Long.MAX_VALUE)
        val count = bytes.copyOfRange(0, 8)
        require(ByteBuffer.wrap(count).long == received)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, receiving + count))
        cipher.updateAAD(session + receiving + count)
        val result = cipher.doFinal(bytes, 8, bytes.size - 8)
        received++
        return result
    }
}
