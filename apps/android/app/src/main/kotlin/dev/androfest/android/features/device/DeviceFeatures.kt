package dev.androfest.android.features.device

import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.MediaMetadata
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.BatteryManager
import dev.androfest.android.features.notifications.BridgeNotificationListener
import dev.androfest.android.features.notifications.NotificationRepository
import dev.twinvia.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class DeviceFeatures(
    private val context: Context,
    private val notifications: NotificationRepository,
    private val scope: CoroutineScope,
) {
    val clipboard = dev.androfest.android.features.clipboard.AutomaticClipboard(context, scope)
    private var ringtone: Ringtone? = null
    private var ringTimeout: Job? = null
    private val _ringing = MutableStateFlow(false)
    val ringing = _ringing.asStateFlow()

    suspend fun execute(command: DeviceCommand): String =
        withContext(Dispatchers.Main.immediate) {
            command.validate()
            when (command.action) {
                DeviceAction.CALL_ANSWER_MAC,
                DeviceAction.CALL_HANDOFF_APPROVE,
                DeviceAction.CALL_END,
                DeviceAction.CALL_AUDIO_START,
                DeviceAction.CALL_AUDIO_STOP ->
                    error("Audio commands must run in the connection service")
                DeviceAction.CONTACTS_LIST,
                DeviceAction.CALLS_LIST,
                DeviceAction.FILES_LIST,
                DeviceAction.FILES_DOWNLOAD -> error("Phone queries must run on the IO dispatcher.")
                DeviceAction.REMOTE_SNAPSHOT,
                DeviceAction.REMOTE_TAP,
                DeviceAction.REMOTE_SWIPE,
                DeviceAction.REMOTE_BACK,
                DeviceAction.REMOTE_HOME,
                DeviceAction.REMOTE_NOTIFICATIONS ->
                    error("Screen control runs in the connection service.")
                DeviceAction.CLIPBOARD_SET -> {
                    clipboard.apply(requireNotNull(command.text))
                    "Clipboard synced to phone."
                }
                DeviceAction.RING -> {
                    stopRinging()
                    ringtone =
                        RingtoneManager.getRingtone(
                            context,
                            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                        ) ?: error("Could not start phone audio.")
                    ringtone!!.audioAttributes =
                        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
                    ringtone!!.isLooping = true
                    ringtone!!.play()
                    _ringing.value = true
                    ringTimeout = scope.launch {
                        delay(20_000)
                        withContext(Dispatchers.Main) { stopRinging() }
                    }
                    "Phone rings for 20 seconds at the current alarm volume."
                }
                DeviceAction.STOP_RINGING -> {
                    stopRinging()
                    "Phone ringer stopped."
                }
                DeviceAction.NOTIFICATION_REPLY,
                DeviceAction.NOTIFICATION_DISMISS ->
                    (notifications.actionHandler
                        ?: error("Enable notification access on your phone."))(command)
                DeviceAction.MEDIA_PLAY_PAUSE,
                DeviceAction.MEDIA_NEXT,
                DeviceAction.MEDIA_PREVIOUS -> {
                    val controller =
                        activeMedia() ?: error("No controllable media session on the phone.")
                    when (command.action) {
                        DeviceAction.MEDIA_NEXT -> controller.transportControls.skipToNext()
                        DeviceAction.MEDIA_PREVIOUS -> controller.transportControls.skipToPrevious()
                        else ->
                            if (controller.playbackState?.state == PlaybackState.STATE_PLAYING)
                                controller.transportControls.pause()
                            else controller.transportControls.play()
                    }
                    "Media command delivered to the app."
                }
            }
        }

    fun stopRinging() {
        ringTimeout?.cancel()
        ringTimeout = null
        ringtone?.stop()
        ringtone = null
        _ringing.value = false
    }

    fun status(): DeviceStatus {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percentage =
            if (level >= 0 && scale > 0) (level * 100 / scale).coerceIn(0, 100) else null
        val charging =
            battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) in
                listOf(BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL)
        val media = activeMedia()
        val locked = context.getSystemService(KeyguardManager::class.java).isDeviceLocked
        val hide = locked && notifications.hideLocked.value
        return DeviceStatus(
            percentage,
            charging,
            locked,
            if (hide) null
            else media?.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE)?.take(512),
            if (hide) null
            else media?.metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)?.take(512),
            media?.playbackState?.state == PlaybackState.STATE_PLAYING,
            ringtone?.isPlaying == true,
        )
    }

    private fun activeMedia(): MediaController? =
        runCatching {
                val sessions =
                    context
                        .getSystemService(MediaSessionManager::class.java)
                        .getActiveSessions(
                            ComponentName(context, BridgeNotificationListener::class.java)
                        )
                sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
                    ?: sessions.firstOrNull()
            }
            .getOrNull()
}
