package dev.androfest.android.core.connection

import dev.androfest.protocol.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.*
import org.junit.Test

class CommandProcessorTest {
    private val now = 1_800_000_000_000L
    private val source = "b82283ab-1934-467d-bb6d-a90fbb35083f"

    private fun request(command: DeviceCommand = DeviceCommand(DeviceAction.RING)) =
        WireCodec.message(MessageType.DEVICE_COMMAND, source, command).copy(timestamp = now)

    @Test
    fun malformedRequestDoesNotPreventNextCommand() = runBlocking {
        var executions = 0
        val processor =
            CommandProcessor(
                CommandHandler { id, _, _ ->
                    executions++
                    CommandResult(id, true, "ok")
                },
                { now },
            )
        assertFalse(
            processor.process(request().copy(payload = JsonObject(emptyMap()))) { true }.success
        )
        assertTrue(processor.process(request()) { true }.success)
        assertEquals(1, executions)
    }

    @Test
    fun duplicateEffectIsExecutedOnceAndScopedToSource() = runBlocking {
        var executions = 0
        val processor =
            CommandProcessor(
                CommandHandler { id, _, _ ->
                    executions++
                    CommandResult(id, true, "ok")
                },
                { now },
            )
        val request = request()
        repeat(2) { assertTrue(processor.process(request) { true }.success) }
        processor.process(request.copy(sourceDeviceId = "da83b21c-0e54-4b8a-acbe-e174384c5765")) {
            true
        }
        assertEquals(2, executions)
    }

    @Test
    fun expiredAndReplacedSessionNeverExecute() = runBlocking {
        var executions = 0
        val processor =
            CommandProcessor(
                CommandHandler { id, _, _ ->
                    executions++
                    CommandResult(id, true, "ok")
                },
                { now },
            )
        assertFalse(processor.process(request().copy(timestamp = now - 90_001)) { true }.success)
        assertFalse(processor.process(request().copy(timestamp = now + 30_001)) { true }.success)
        assertFalse(processor.process(request()) { false }.success)
        assertEquals(0, executions)
    }

    @Test
    fun failedReadRechecksPermissionOnDuplicate() = runBlocking {
        var executions = 0
        val processor =
            CommandProcessor(
                CommandHandler { id, _, _ ->
                    executions++
                    if (executions == 1) error("Permission denied")
                    CommandResult(id, true, "Allowed after permission change")
                },
                { now },
            )
        val request = request(DeviceCommand(DeviceAction.CONTACTS_LIST, browse = PhoneQuery()))
        assertFalse(processor.process(request) { true }.success)
        assertTrue(processor.process(request) { true }.success)
        assertEquals(2, executions)
    }

    @Test
    fun boundedHistoryEvictsOldestEffect() = runBlocking {
        var executions = 0
        val processor =
            CommandProcessor(
                CommandHandler { id, _, _ ->
                    executions++
                    CommandResult(id, true, "ok")
                },
                { now },
                capacity = 2,
            )
        val oldest = request()
        processor.process(oldest) { true }
        repeat(2) { processor.process(request()) { true } }
        processor.process(oldest) { true }
        assertEquals(4, executions)
    }

    @Test
    fun timestampBoundsApplyBeforeCachedResults() = runBlocking {
        var executions = 0
        val processor =
            CommandProcessor(
                CommandHandler { id, _, _ ->
                    executions++
                    CommandResult(id, true, "ok")
                },
                { now },
            )
        val value = request()
        assertTrue(processor.process(value.copy(timestamp = now - 90_000)) { true }.success)
        assertTrue(processor.process(request().copy(timestamp = now + 30_000)) { true }.success)
        assertFalse(processor.process(value.copy(timestamp = now - 90_001)) { true }.success)
        val invalid =
            request()
                .copy(
                    payload =
                        WireCodec.json.encodeToJsonElement(
                            DeviceCommand.serializer(),
                            DeviceCommand(DeviceAction.RING, text = "invalid"),
                        ) as JsonObject
                )
        assertFalse(processor.process(invalid) { true }.success)
        assertEquals(2, executions)
    }

    @Test
    fun cancellationPropagatesAndErrorsAreBounded() = runBlocking {
        val cancelled =
            CommandProcessor(CommandHandler { _, _, _ -> throw CancellationException() }, { now })
        try {
            cancelled.process(request()) { true }
            fail("Cancellation swallowed")
        } catch (_: CancellationException) {}
        val failure =
            CommandProcessor(CommandHandler { _, _, _ -> error("x".repeat(1024)) }, { now })
        assertEquals(128, failure.process(request()) { true }.message.length)
    }
}
