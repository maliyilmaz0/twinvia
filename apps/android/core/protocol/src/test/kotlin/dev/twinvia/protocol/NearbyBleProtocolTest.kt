package dev.twinvia.protocol

import kotlinx.serialization.Serializable
import org.junit.Assert.*
import org.junit.Test

class NearbyBleProtocolTest {
    @Serializable private data class Vector(val invitation: PairingInvitation)

    @Test
    fun `independent discovery vector and roles match Swift`() {
        val value =
            WireCodec.json
                .decodeFromString<Vector>(
                    requireNotNull(
                            javaClass.classLoader?.getResource("pairing/native-pairing.json")
                        )
                        .readText()
                )
                .invitation
        fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
        assertEquals(
            "dev.androfest.ble.208ef8258436f653961a5e8c",
            NearbyBleProtocol.serviceId(value),
        )
        assertEquals(
            "4fdf32c91101401eee477ab1cb8795e8",
            hex(NearbyBleProtocol.context("mac", value)),
        )
        assertEquals(
            "e8bce6b6ff151b604f4e92e3f92dadd8",
            hex(NearbyBleProtocol.context("phone", value)),
        )
        assertNotEquals(
            NearbyBleProtocol.serviceId(value),
            NearbyBleProtocol.serviceId(value.copy(secret = "b2".repeat(32))),
        )
    }

    @Test
    fun `frame vector and malformed bounds`() {
        val vector =
            "0201020304c59fc49ff09f9880".chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        val packet = NearbyBleProtocol.decode(vector)
        assertEquals(0x01020304, packet.sequence)
        assertEquals("şğ😀", packet.data.toString(Charsets.UTF_8))
        assertArrayEquals(vector, NearbyBleProtocol.encode(packet))
        for (bytes in
            listOf(
                byteArrayOf(),
                byteArrayOf(3, 0, 0, 0),
                byteArrayOf(3, 0, 0, 0, 0, 0),
                byteArrayOf(2, 0, 0, 0, 0),
                byteArrayOf(4, 0, 0, 0, 0),
                byteArrayOf(2, 0, 0, 0, 0) + ByteArray(8193),
            )) {
            assertThrows(IllegalArgumentException::class.java) { NearbyBleProtocol.decode(bytes) }
        }
        assertThrows(IllegalArgumentException::class.java) {
            NearbyBleProtocol.encode(NearbyBleProtocol.Packet(2, data = ByteArray(8193)))
        }
        assertEquals(-1, NearbyBleProtocol.decode(byteArrayOf(3, -1, -1, -1, -1)).sequence)
    }
}
