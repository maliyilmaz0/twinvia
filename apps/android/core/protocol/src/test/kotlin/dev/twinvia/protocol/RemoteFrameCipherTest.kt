package dev.twinvia.protocol

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class RemoteFrameCipherTest {
    @Test
    fun `cross platform vector rejects reflection tampering replay and reordering`() {
        val vector =
            Json.parseToJsonElement(
                    requireNotNull(javaClass.classLoader?.getResource("remote-fast-vector.json"))
                        .readText()
                )
                .jsonObject
        fun value(name: String) = requireNotNull(vector[name]).jsonPrimitive.content
        val channel = RemoteChannel(value("session"), value("key"))
        val mac = RemoteFrameCipher(channel, mac = true)
        val phone = RemoteFrameCipher(channel, mac = false)
        val frame = mac.seal(value("plain").toByteArray())
        assertEquals(value("sealed"), frame.joinToString("") { "%02x".format(it) })
        assertThrows(Exception::class.java) { mac.open(frame) }
        val corrupt = frame.copyOf().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() }
        assertThrows(Exception::class.java) { phone.open(corrupt) }
        val next = mac.seal("next".toByteArray())
        assertThrows(Exception::class.java) { phone.open(next) }
        assertEquals(value("plain"), phone.open(frame).decodeToString())
        assertThrows(Exception::class.java) { phone.open(frame) }
        assertEquals("next", phone.open(next).decodeToString())
        assertEquals("response", mac.open(phone.seal("response".toByteArray())).decodeToString())
        assertThrows(IllegalArgumentException::class.java) {
            mac.seal(ByteArray(WireCodec.MAX_MESSAGE_BYTES + 1))
        }
    }

    @org.junit.Test
    fun `local endpoints are bounded canonical private IPv4 only`() {
        val key = java.util.Base64.getEncoder().encodeToString(ByteArray(32) { 1 })
        for (host in
            listOf("10.0.0.1", "172.16.0.1", "172.31.255.254", "192.168.1.76")) RemoteChannel(
                java.util.UUID.randomUUID().toString(),
                key,
                host,
                54321,
            )
            .validate()
        for (host in
            listOf(
                "example.com",
                "127.0.0.1",
                "8.8.8.8",
                "172.32.0.1",
                "192.168.001.2",
                "192.168.1.999",
                "192.168.1.2%wlan0",
            )) org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            RemoteChannel(java.util.UUID.randomUUID().toString(), key, host, 54321).validate()
        }
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            RemoteChannel(java.util.UUID.randomUUID().toString(), key, "192.168.1.2", 80).validate()
        }
    }
}
