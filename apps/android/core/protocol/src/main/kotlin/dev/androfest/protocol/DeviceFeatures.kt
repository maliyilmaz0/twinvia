package dev.androfest.protocol

import kotlinx.serialization.Serializable

@Serializable
enum class DeviceAction {
    @kotlinx.serialization.SerialName("call.answer.mac") CALL_ANSWER_MAC,
    @kotlinx.serialization.SerialName("call.handoff.approve") CALL_HANDOFF_APPROVE,
    @kotlinx.serialization.SerialName("call.end") CALL_END,
    @kotlinx.serialization.SerialName("call.audio.start") CALL_AUDIO_START,
    @kotlinx.serialization.SerialName("call.audio.stop") CALL_AUDIO_STOP,
    @kotlinx.serialization.SerialName("contacts.list") CONTACTS_LIST,
    @kotlinx.serialization.SerialName("calls.list") CALLS_LIST,
    @kotlinx.serialization.SerialName("files.list") FILES_LIST,
    @kotlinx.serialization.SerialName("files.download") FILES_DOWNLOAD,
    @kotlinx.serialization.SerialName("clipboard.set") CLIPBOARD_SET,
    @kotlinx.serialization.SerialName("device.ring") RING,
    @kotlinx.serialization.SerialName("device.ring.stop") STOP_RINGING,
    @kotlinx.serialization.SerialName("notification.reply") NOTIFICATION_REPLY,
    @kotlinx.serialization.SerialName("notification.dismiss") NOTIFICATION_DISMISS,
    @kotlinx.serialization.SerialName("media.playPause") MEDIA_PLAY_PAUSE,
    @kotlinx.serialization.SerialName("media.next") MEDIA_NEXT,
    @kotlinx.serialization.SerialName("media.previous") MEDIA_PREVIOUS,
}

@Serializable
data class DeviceCommand(
    val action: DeviceAction,
    val text: String? = null,
    val key: String? = null,
    val actionToken: String? = null,
    val browse: PhoneQuery? = null,
) {
    fun validate() {
        if (
            action in
                listOf(
                    DeviceAction.CONTACTS_LIST,
                    DeviceAction.CALLS_LIST,
                    DeviceAction.FILES_LIST,
                    DeviceAction.FILES_DOWNLOAD,
                )
        ) {
            require(text == null && key == null && actionToken == null && browse != null)
            browse.validate()
            if (action == DeviceAction.FILES_DOWNLOAD)
                require(
                    !browse.path.isNullOrEmpty() && browse.query.isEmpty() && browse.offset == 0
                )
            if (action == DeviceAction.CONTACTS_LIST || action == DeviceAction.CALLS_LIST)
                require(browse.path == null)
            return
        }
        require(browse == null)
        when (action) {
            DeviceAction.CALL_ANSWER_MAC,
            DeviceAction.CALL_HANDOFF_APPROVE,
            DeviceAction.CALL_END,
            DeviceAction.CALL_AUDIO_START,
            DeviceAction.CALL_AUDIO_STOP ->
                require(text == null && key == null && actionToken?.matches(UUID_PATTERN) == true)
            DeviceAction.CLIPBOARD_SET ->
                require(
                    !text.isNullOrEmpty() &&
                        text.length <= 16_384 &&
                        key == null &&
                        actionToken == null
                )
            DeviceAction.NOTIFICATION_REPLY,
            DeviceAction.NOTIFICATION_DISMISS -> {
                require(
                    !key.isNullOrBlank() &&
                        key.length <= 4096 &&
                        actionToken?.matches(UUID_PATTERN) == true
                )
                if (action == DeviceAction.NOTIFICATION_REPLY)
                    require(!text.isNullOrBlank() && text.length <= 4096)
                else require(text == null)
            }
            else -> require(text == null && key == null && actionToken == null)
        }
    }

    companion object {
        private val UUID_PATTERN =
            Regex("[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}")
    }
}

@Serializable
data class CommandResult(
    val requestId: String,
    val success: Boolean,
    val message: String,
    val data: PhonePage? = null,
)

@Serializable
data class DeviceStatus(
    val batteryPercent: Int?,
    val charging: Boolean,
    val locked: Boolean,
    val mediaTitle: String? = null,
    val mediaArtist: String? = null,
    val mediaPlaying: Boolean = false,
    val ringing: Boolean = false,
    val call: PhoneCallState? = null,
)

@Serializable data class SharedText(val text: String, val isClipboard: Boolean? = null)

@Serializable
data class PhoneCallState(
    val state: String,
    val token: String? = null,
    val approval: String? = null,
) {
    fun validate() {
        require(state in setOf("idle", "ringing", "active"))
        if (state == "idle") require(token == null && approval == null)
        else {
            require(
                token != null &&
                    runCatching { java.util.UUID.fromString(token).toString().equals(token, true) }
                        .getOrDefault(false)
            )
            require(
                approval == null ||
                    runCatching {
                            java.util.UUID.fromString(approval).toString().equals(approval, true)
                        }
                        .getOrDefault(false)
            )
        }
    }
}
