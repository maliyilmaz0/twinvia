package dev.androfest.android.core.connection

import android.content.Context
import dev.androfest.android.features.calls.CallAudioRelay
import dev.androfest.android.features.calls.PhoneCallHandoff
import dev.androfest.android.features.device.DeviceFeatures
import dev.androfest.android.features.device.PhoneDataProvider
import dev.androfest.android.features.remote.RemoteAccessibilityService
import dev.androfest.android.features.remote.RemoteControlSession
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
    private val context: Context,
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
            command.action in
                setOf(
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
                ) -> {
                RemoteControlSession.requireActive(context)
                check(isCurrent()) { "The connection changed." }
                val service =
                    RemoteAccessibilityService.current
                        ?: error("Enable Twinvia screen control in Accessibility settings.")
                when (command.action) {
                    DeviceAction.REMOTE_FAST_OPEN -> {
                        val channel =
                            withContext(Dispatchers.IO) {
                                dev.androfest.android.features.remote.FastScreenServer.open(context)
                            }
                        RemoteControlSession.requireActive(context)
                        CommandResult(
                            id,
                            true,
                            "Bluetooth Classic screen lane is ready to connect.",
                            channel = channel,
                        )
                    }
                    DeviceAction.REMOTE_SNAPSHOT,
                    DeviceAction.REMOTE_SNAPSHOT_DETAIL -> {
                        val screen =
                            service.snapshot(command.action == DeviceAction.REMOTE_SNAPSHOT_DETAIL)
                        RemoteControlSession.requireActive(context)
                        check(isCurrent()) { "The connection changed." }
                        CommandResult(id, true, "Phone screen updated.", screen = screen)
                    }
                    DeviceAction.REMOTE_TEXT,
                    DeviceAction.REMOTE_KEY -> {
                        RemoteControlSession.requireControlActive(context)
                        withContext(Dispatchers.Main.immediate) {
                            check(isCurrent()) { "The connection changed." }
                            RemoteControlSession.requireControlActive(context)
                            service.type(command.text, command.key)
                        }
                        CommandResult(id, true, "Keyboard input sent.")
                    }
                    DeviceAction.REMOTE_TAP -> {
                        RemoteControlSession.requireControlActive(context)
                        val coordinates = requireNotNull(command.key).split(',').map(String::toInt)
                        service.tap(coordinates[0], coordinates[1])
                        CommandResult(id, true, "Touch sent to phone.")
                    }
                    DeviceAction.REMOTE_SWIPE -> {
                        RemoteControlSession.requireControlActive(context)
                        val gesture = requireNotNull(command.key).split(',').map(String::toInt)
                        service.swipe(gesture[0], gesture[1], gesture[2], gesture[3], gesture[4])
                        CommandResult(id, true, "Swipe sent to phone.")
                    }
                    else -> {
                        RemoteControlSession.requireControlActive(context)
                        val action =
                            when (command.action) {
                                DeviceAction.REMOTE_BACK ->
                                    android.accessibilityservice.AccessibilityService
                                        .GLOBAL_ACTION_BACK
                                DeviceAction.REMOTE_HOME ->
                                    android.accessibilityservice.AccessibilityService
                                        .GLOBAL_ACTION_HOME
                                else ->
                                    android.accessibilityservice.AccessibilityService
                                        .GLOBAL_ACTION_NOTIFICATIONS
                            }
                        check(
                            withContext(Dispatchers.Main.immediate) {
                                service.performGlobalAction(action)
                            }
                        ) {
                            "Phone could not perform this navigation action."
                        }
                        CommandResult(id, true, "Navigation sent to phone.")
                    }
                }
            }
            else ->
                withContext(Dispatchers.Main.immediate) {
                    check(isCurrent()) { "The session changed; the command was not applied." }
                    CommandResult(id, true, features.execute(command))
                }
        }
    }
}
