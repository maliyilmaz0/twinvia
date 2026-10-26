package dev.twinvia.protocol

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

object NearbyBleProtocol {
    const val MAX_CHUNK = 8192

    private fun mac(domain: String, invitation: PairingInvitation): ByteArray {
        require(invitation.secret.matches(Regex("[a-f0-9]{64}")))
        val key = invitation.secret.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        return Mac.getInstance("HmacSHA256")
            .apply { init(SecretKeySpec(key, "HmacSHA256")) }
            .doFinal(
                ("androfest.nearby.ble.v1.$domain\n" + invitation.id).toByteArray(Charsets.UTF_8)
            )
    }

    fun serviceId(invitation: PairingInvitation) =
        "dev.androfest.ble." +
            mac("service", invitation).take(12).joinToString("") { "%02x".format(it) }

    fun context(role: String, invitation: PairingInvitation): ByteArray {
        require(role == "mac" || role == "phone")
        return mac("endpoint.$role", invitation).copyOf(16)
    }

    data class Packet(val kind: Int, val sequence: Int = 0, val data: ByteArray = byteArrayOf())

    fun encode(packet: Packet): ByteArray =
        when (packet.kind) {
            1 -> {
                require(packet.data.size in 112..175)
                byteArrayOf(1) + packet.data
            }
            2 -> {
                require(packet.data.size in 1..MAX_CHUNK)
                ByteBuffer.allocate(5 + packet.data.size)
                    .put(2)
                    .putInt(packet.sequence)
                    .put(packet.data)
                    .array()
            }
            3 -> ByteBuffer.allocate(5).put(3).putInt(packet.sequence).array()
            else -> error("Unknown BLE packet")
        }

    fun decode(bytes: ByteArray): Packet {
        require(bytes.isNotEmpty())
        val kind = bytes[0].toInt()
        if (kind == 1) {
            require(bytes.size in 113..176)
            return Packet(1, data = bytes.copyOfRange(1, bytes.size))
        }
        require(kind == 2 || kind == 3)
        require(bytes.size >= 5)
        val sequence = ByteBuffer.wrap(bytes, 1, 4).int
        return when (kind) {
            2 -> {
                require(bytes.size in 6..(MAX_CHUNK + 5))
                Packet(2, sequence, bytes.copyOfRange(5, bytes.size))
            }
            3 -> {
                require(bytes.size == 5)
                Packet(3, sequence)
            }
            else -> error("Unknown BLE packet")
        }
    }
}
