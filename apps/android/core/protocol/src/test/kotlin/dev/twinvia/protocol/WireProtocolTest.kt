package dev.twinvia.protocol

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class WireProtocolTest {
    private fun fixture(name: String) =
        requireNotNull(javaClass.classLoader?.getResource(name)).readText()

    private fun altered(name: String, change: MutableMap<String, JsonElement>.() -> Unit): String {
        val fields = WireCodec.json.parseToJsonElement(fixture(name)).jsonObject.toMutableMap()
        fields.change()
        return JsonObject(fields).toString()
    }

    @Test
    fun `all shared fixtures round trip`() {
        listOf(
                "device-hello.json",
                "notification-posted.json",
                "notification-replay.json",
                "notification-removed.json",
                "file-offer.json",
                "file-accept.json",
                "file-complete.json",
                "file-cancel.json",
            )
            .forEach {
                val decoded = WireCodec.decode(fixture(it))
                assertEquals(decoded, WireCodec.decode(WireCodec.encode(decoded)))
            }
        assertTrue(
            WireCodec.json
                .decodeFromJsonElement<NotificationPosted>(
                    WireCodec.decode(fixture("notification-replay.json")).payload
                )
                .isReplay == true
        )
        assertNull(
            WireCodec.json
                .decodeFromJsonElement<NotificationPosted>(
                    WireCodec.decode(fixture("notification-posted.json")).payload
                )
                .isReplay
        )
    }

    @Test
    fun `unicode notification content survives`() {
        val notification =
            WireCodec.json.decodeFromJsonElement<NotificationPosted>(
                WireCodec.decode(fixture("notification-posted.json")).payload
            )
        assertEquals("Merhaba Mac 👋", notification.text)
    }

    @Test
    fun `notification icon remains optional and survives encoding`() {
        val old =
            WireCodec.json.decodeFromJsonElement<NotificationPosted>(
                WireCodec.decode(fixture("notification-posted.json")).payload
            )
        assertNull(old.appIconPng)
        val rich = WireCodec.decode(fixture("notification-with-icon.json"))
        assertEquals(rich, WireCodec.decode(WireCodec.encode(rich)))
        assertNotNull(
            WireCodec.json.decodeFromJsonElement<NotificationPosted>(rich.payload).appIconPng
        )
    }

    @Test
    fun `invalid or oversized icon rejected`() {
        listOf(
                "not base64",
                java.util.Base64.getEncoder().encodeToString(ByteArray(24)),
                "A".repeat(87_388),
            )
            .forEach { value ->
                assertThrows(IllegalArgumentException::class.java) {
                    WireCodec.decode(
                        altered("notification-posted.json") {
                            put(
                                "payload",
                                JsonObject(
                                    getValue("payload").jsonObject +
                                        ("appIconPng" to JsonPrimitive(value))
                                ),
                            )
                        }
                    )
                }
            }
    }

    @Test
    fun `unsupported protocol version rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.decode(altered("device-hello.json") { put("version", JsonPrimitive(2)) })
        }
    }

    @Test
    fun `unknown message type rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.decode(
                altered("device-hello.json") { put("type", JsonPrimitive("command.execute")) }
            )
        }
    }

    @Test
    fun `invalid device id rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.decode(
                altered("device-hello.json") { put("sourceDeviceId", JsonPrimitive("not-a-uuid")) }
            )
        }
    }

    @Test
    fun `missing required payload rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.decode(altered("file-offer.json") { put("payload", JsonObject(emptyMap())) })
        }
    }

    @Test
    fun `unsafe file names rejected`() {
        listOf("../secret", "folder/file.txt", "folder\\file.txt", "..", ".", "bad\u0000name", " ")
            .forEach { name ->
                assertThrows(IllegalArgumentException::class.java) {
                    WireCodec.decode(
                        altered("file-offer.json") {
                            put(
                                "payload",
                                JsonObject(
                                    getValue("payload").jsonObject +
                                        ("fileName" to JsonPrimitive(name))
                                ),
                            )
                        }
                    )
                }
            }
    }

    @Test
    fun `invalid hash or negative length rejected`() {
        listOf(
                "sha256" to JsonPrimitive("bad"),
                "sha256" to JsonPrimitive("a".repeat(64) + "\n"),
                "size" to JsonPrimitive(-1),
            )
            .forEach { (key, value) ->
                assertThrows(IllegalArgumentException::class.java) {
                    WireCodec.decode(
                        altered("file-offer.json") {
                            put(
                                "payload",
                                JsonObject(getValue("payload").jsonObject + (key to value)),
                            )
                        }
                    )
                }
            }
    }

    @Test
    fun `oversize control message rejected before decoding`() {
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.decode(" ".repeat(WireCodec.MAX_MESSAGE_BYTES + 1))
        }
    }

    @Test
    fun `negative resume offset rejected`() {
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.decode(
                altered("file-accept.json") {
                    put(
                        "payload",
                        JsonObject(
                            getValue("payload").jsonObject + ("offset" to JsonPrimitive(-1))
                        ),
                    )
                }
            )
        }
    }

    @Test
    fun `additive fields allowed`() {
        val decoded =
            WireCodec.decode(
                altered("device-hello.json") { put("futureField", JsonPrimitive(true)) }
            )
        assertEquals(MessageType.DEVICE_HELLO, decoded.type)
    }
}
