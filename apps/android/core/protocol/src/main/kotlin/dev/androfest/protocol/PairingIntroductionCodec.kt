package dev.androfest.protocol

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.util.UUID

object PairingIntroductionCodec {
    fun compactName(name: String): String {
        val result = StringBuilder()
        name.codePoints().forEachOrdered { cp ->
            val next = String(Character.toChars(cp))
            if ((result.toString() + next).toByteArray(Charsets.UTF_8).size <= 64)
                result.append(next)
        }
        return result.toString().ifBlank { "Android" }
    }

    fun encodeIntroduction(intro: PairingIntroduction): ByteArray {
        val name = intro.name.toByteArray(Charsets.UTF_8)
        require(name.size in 1..64 && intro.port in 1024..65535)
        val id = UUID.fromString(intro.deviceId)
        fun bytes(hex: String, count: Int): ByteArray {
            require(hex.matches(Regex("[a-f0-9]{${count * 2}}")))
            return hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        }
        val buffer = ByteArrayOutputStream()
        DataOutputStream(buffer).use { out ->
            out.writeBytes("AFN1")
            out.writeLong(id.mostSignificantBits)
            out.writeLong(id.leastSignificantBits)
            out.writeShort(intro.port)
            out.write(bytes(intro.fingerprint, 32))
            out.write(bytes(intro.nonce, 16))
            out.writeLong(intro.timestamp)
            out.writeByte(name.size)
            out.write(name)
            out.write(bytes(intro.proof, 32))
        }
        return buffer.toByteArray()
    }
}
