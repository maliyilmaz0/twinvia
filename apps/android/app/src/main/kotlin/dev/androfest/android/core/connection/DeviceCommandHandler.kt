package dev.androfest.android.core.connection

import dev.androfest.android.features.calls.CallAudioRelay
import dev.androfest.android.features.calls.PhoneCallHandoff
import dev.androfest.android.features.device.DeviceFeatures
import dev.androfest.android.features.device.PhoneDataProvider
import dev.twinvia.protocol.CommandResult
import dev.twinvia.protocol.DeviceAction
import dev.twinvia.protocol.DeviceCommand
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Platform action dispatch. Command validation and duplicate history are owned by CommandProcessor.
 */
class DeviceCommandHandler(
    private val handoff: PhoneCallHandoff,
    private val audio: CallAudioRelay,
    private val phoneData: PhoneDataProvider,
    private val features: DeviceFeatures,
) : CommandHandler {
    override suspend fun execute(
        requestId: String,
        command: DeviceCommand,
        isCurrent: () -> Boolean,
    ): CommandResult {
        val id = requestId
        check(isCurrent()) { "The session changed; the command was not applied." }
        return when {
            command.action in PhoneCallHandoff.actions ->
                withContext(Dispatchers.Main.immediate) {
                    check(isCurrent()) { "The session changed; the command was not applied." }
                    CommandResult(id, true, handoff.execute(command))
                }
            command.action == DeviceAction.CALL_AUDIO_START ||
                command.action == DeviceAction.CALL_AUDIO_STOP -> {
                if (command.action == DeviceAction.CALL_AUDIO_START)
                    audio.start(requireNotNull(command.actionToken))
                else {
                    audio.stop(command.actionToken)
                    withContext(Dispatchers.Main.immediate) {
                        if (isCurrent()) handoff.revokeApproval()
                    }
                }
                CommandResult(id, true, "Call audio command applied")
            }
            command.action in PhoneDataProvider.actions -> phoneData.execute(id, command)
            else ->
                withContext(Dispatchers.Main.immediate) {
                    check(isCurrent()) { "The session changed; the command was not applied." }
                    CommandResult(id, true, features.execute(command))
                }
        }
    }
}
