package dev.androfest.android.core.connection

import dev.twinvia.protocol.CommandResult
import dev.twinvia.protocol.DeviceAction
import dev.twinvia.protocol.DeviceCommand
import dev.twinvia.protocol.WireCodec
import dev.twinvia.protocol.WireEnvelope
import kotlinx.coroutines.CancellationException

/** Platform effects are supplied by the composition root, never by this policy. */
fun interface CommandHandler {
    suspend fun execute(
        requestId: String,
        command: DeviceCommand,
        isCurrent: () -> Boolean,
    ): CommandResult
}

/** Owned by the single command consumer. Invalid input must not terminate that consumer. */
class CommandProcessor(
    private val handler: CommandHandler,
    private val now: () -> Long = System::currentTimeMillis,
    private val capacity: Int = 128,
) {
    init {
        require(capacity > 0)
    }

    private val results = linkedMapOf<Pair<String, String>, CommandResult>()

    suspend fun process(request: WireEnvelope, isCurrent: () -> Boolean): CommandResult {
        return try {
            check(isCurrent()) { "The session changed; the command was not applied." }
            check(now() - request.timestamp in -30_000L..90_000L) { "The command expired." }
            val command =
                WireCodec.json.decodeFromJsonElement(DeviceCommand.serializer(), request.payload)
            command.validate()
            val key = request.sourceDeviceId to request.id
            if (cacheable(command.action))
                results[key]?.let {
                    return it
                }
            val result = handler.execute(request.id, command, isCurrent)
            if (cacheable(command.action) && result.data == null) {
                results[key] = result
                if (results.size > capacity) results.remove(results.keys.first())
            }
            result
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            CommandResult(
                request.id,
                false,
                (failure.message ?: "Could not apply the command.").take(128),
            )
        }
    }

    private fun cacheable(action: DeviceAction) =
        action !in
            setOf(
                DeviceAction.CONTACTS_LIST,
                DeviceAction.CALLS_LIST,
                DeviceAction.FILES_LIST,
                DeviceAction.FILES_DOWNLOAD,
                DeviceAction.CALL_AUDIO_START,
                DeviceAction.CALL_AUDIO_STOP,
                DeviceAction.REMOTE_SNAPSHOT,
                DeviceAction.REMOTE_SNAPSHOT_DETAIL,
                DeviceAction.REMOTE_FAST_OPEN,
                DeviceAction.REMOTE_TEXT,
                DeviceAction.REMOTE_KEY,
                DeviceAction.REMOTE_TAP,
                DeviceAction.REMOTE_SWIPE,
                DeviceAction.REMOTE_BACK,
                DeviceAction.REMOTE_HOME,
                DeviceAction.REMOTE_NOTIFICATIONS,
            )
}
