package dev.androfest.protocol

import org.junit.Assert.*
import org.junit.Test

class DeviceFeaturesTest {
    private val id = "12345678-1234-1234-1234-123456789abc"

    @Test
    fun `shared fixtures decode and round trip`() {
        listOf(
                "device-command",
                "command-result",
                "device-status",
                "device-status-call",
                "shared-text",
                "clipboard-text",
                "phone-contacts",
                "phone-calls",
                "phone-files",
            )
            .forEach { name ->
                val fixture =
                    requireNotNull(javaClass.classLoader?.getResource("$name.json")).readText()
                val envelope = WireCodec.decode(fixture)
                assertEquals(envelope, WireCodec.decode(WireCodec.encode(envelope)))
            }
    }

    @Test
    fun `phone queries reject traversal and unbounded offsets`() {
        listOf("../secret", "/data/data", "x/../secret", "x/./y").forEach { path ->
            assertThrows(IllegalArgumentException::class.java) {
                DeviceCommand(DeviceAction.FILES_LIST, browse = PhoneQuery(path = path)).validate()
            }
        }
        assertThrows(IllegalArgumentException::class.java) { PhoneQuery(offset = -1).validate() }
    }

    @Test
    fun `notification actions require current reference and bounded text`() {
        listOf(
                DeviceCommand(DeviceAction.NOTIFICATION_REPLY, "hello", "key"),
                DeviceCommand(DeviceAction.NOTIFICATION_REPLY, " ", "key", id),
                DeviceCommand(DeviceAction.NOTIFICATION_REPLY, "a".repeat(4097), "key", id),
                DeviceCommand(DeviceAction.NOTIFICATION_DISMISS, "extra", "key", id),
                DeviceCommand(DeviceAction.RING, key = "extra"),
            )
            .forEach { command ->
                assertThrows(IllegalArgumentException::class.java) { command.validate() }
            }
    }

    @Test
    fun `control actions and unicode bounds`() {
        listOf(
                DeviceAction.RING,
                DeviceAction.STOP_RINGING,
                DeviceAction.MEDIA_NEXT,
                DeviceAction.MEDIA_PREVIOUS,
                DeviceAction.MEDIA_PLAY_PAUSE,
            )
            .forEach { DeviceCommand(it).validate() }
        DeviceCommand(DeviceAction.CLIPBOARD_SET, "👋".repeat(8192)).validate()
        assertThrows(IllegalArgumentException::class.java) {
            DeviceCommand(DeviceAction.CLIPBOARD_SET, "👋".repeat(8193)).validate()
        }
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.message(MessageType.DEVICE_STATUS, id, DeviceStatus(101, false, false))
        }
        assertThrows(IllegalArgumentException::class.java) {
            WireCodec.message(MessageType.COMMAND_RESULT, id, CommandResult("bad", true, "ok"))
        }
    }

    @Test
    fun `call actions require current call reference and call status rejects invalid consent`() {
        for (action in
            listOf(
                DeviceAction.CALL_ANSWER_MAC,
                DeviceAction.CALL_HANDOFF_APPROVE,
                DeviceAction.CALL_END,
            )) {
            assertThrows(IllegalArgumentException::class.java) { DeviceCommand(action).validate() }
            DeviceCommand(action, actionToken = id).validate()
            assertThrows(IllegalArgumentException::class.java) {
                DeviceCommand(action, text = "unexpected", actionToken = id).validate()
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            PhoneCallState("idle", id, id).validate()
        }
        assertThrows(IllegalArgumentException::class.java) {
            PhoneCallState("active", null, id).validate()
        }
        assertThrows(IllegalArgumentException::class.java) {
            PhoneCallState("active", id, "bad").validate()
        }
    }
}
