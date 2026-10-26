package dev.androfest.protocol

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

@Serializable
enum class MessageType {
    @kotlinx.serialization.SerialName("device.hello") DEVICE_HELLO,
    @kotlinx.serialization.SerialName("notification.posted") NOTIFICATION_POSTED,
    @kotlinx.serialization.SerialName("notification.removed") NOTIFICATION_REMOVED,
    @kotlinx.serialization.SerialName("file.offer") FILE_OFFER,
    @kotlinx.serialization.SerialName("file.accept") FILE_ACCEPT,
    @kotlinx.serialization.SerialName("file.complete") FILE_COMPLETE,
    @kotlinx.serialization.SerialName("file.cancel") FILE_CANCEL,
    @kotlinx.serialization.SerialName("device.command") DEVICE_COMMAND,
    @kotlinx.serialization.SerialName("command.result") COMMAND_RESULT,
    @kotlinx.serialization.SerialName("device.status") DEVICE_STATUS,
    @kotlinx.serialization.SerialName("text.shared") TEXT_SHARED,
}

@Serializable
data class WireEnvelope(
    val version: Int,
    val id: String,
    val type: MessageType,
    val timestamp: Long,
    val sourceDeviceId: String,
    val payload: JsonObject,
)

@Serializable
data class DeviceHello(
    val name: String,
    val platform: String,
    val osVersion: String,
    val capabilities: List<String>,
)

@Serializable
data class NotificationPosted(
    val key: String,
    val packageName: String,
    val appName: String,
    val title: String? = null,
    val text: String? = null,
    val postedAt: Long,
    val canReply: Boolean,
    val appIconPng: String? = null,
    val actionToken: String? = null,
    val canDismiss: Boolean? = null,
    val isReplay: Boolean? = null,
)

@Serializable data class NotificationRemoved(val key: String)

@Serializable
data class FileOffer(
    val transferId: String,
    val fileName: String,
    val mimeType: String,
    val size: Long,
    val sha256: String,
)

@Serializable data class FileAccept(val transferId: String, val offset: Long)

@Serializable data class FileComplete(val transferId: String, val sha256: String)

@Serializable data class FileCancel(val transferId: String, val reason: String? = null)

object WireCodec {
    const val MAX_MESSAGE_BYTES = 262_144
    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun encode(envelope: WireEnvelope): String {
        validate(envelope)
        return json.encodeToString(envelope).also {
            require(it.toByteArray(Charsets.UTF_8).size <= MAX_MESSAGE_BYTES) {
                "Message too large"
            }
        }
    }

    fun decode(text: String): WireEnvelope {
        require(text.toByteArray(Charsets.UTF_8).size <= MAX_MESSAGE_BYTES) { "Message too large" }
        return json.decodeFromString<WireEnvelope>(text).also(::validate)
    }

    inline fun <reified T> message(
        type: MessageType,
        sourceDeviceId: String,
        payload: T,
    ): WireEnvelope =
        WireEnvelope(
                version = 1,
                id = UUID.randomUUID().toString(),
                type = type,
                timestamp = System.currentTimeMillis(),
                sourceDeviceId = sourceDeviceId,
                payload = json.encodeToJsonElement(payload) as JsonObject,
            )
            .also(::validate)

    fun validate(envelope: WireEnvelope) {
        require(envelope.version == 1) { "Unsupported protocol version" }
        require(isUUID(envelope.id) && isUUID(envelope.sourceDeviceId)) {
            "Invalid message or device ID"
        }
        require(envelope.timestamp > 0 && envelope.timestamp <= 9_007_199_254_740_991L)
        when (envelope.type) {
            MessageType.DEVICE_HELLO ->
                json.decodeFromJsonElement<DeviceHello>(envelope.payload).let {
                    require(it.name.isNotBlank() && it.osVersion.isNotBlank())
                    require(it.platform in listOf("android", "macos"))
                    require(it.capabilities.distinct().size == it.capabilities.size)
                    require(it.capabilities.all { capability -> capability.isNotBlank() })
                }
            MessageType.NOTIFICATION_POSTED ->
                json.decodeFromJsonElement<NotificationPosted>(envelope.payload).let {
                    require(
                        it.key.isNotBlank() &&
                            it.packageName.isNotBlank() &&
                            it.appName.isNotBlank()
                    )
                    require(it.postedAt > 0 && it.postedAt <= 9_007_199_254_740_991L)
                    require(it.actionToken == null || isUUID(it.actionToken))
                    it.appIconPng?.let { icon ->
                        require(icon.length <= 87_384)
                        val bytes = java.util.Base64.getDecoder().decode(icon)
                        require(
                            bytes.size in 24..65_536 &&
                                bytes.take(8) ==
                                    listOf(137, 80, 78, 71, 13, 10, 26, 10).map(Int::toByte)
                        )
                        val header = java.nio.ByteBuffer.wrap(bytes)
                        require(header.getInt(16) in 1..256 && header.getInt(20) in 1..256)
                    }
                }
            MessageType.NOTIFICATION_REMOVED ->
                require(
                    json
                        .decodeFromJsonElement<NotificationRemoved>(envelope.payload)
                        .key
                        .isNotBlank()
                )
            MessageType.FILE_OFFER ->
                json.decodeFromJsonElement<FileOffer>(envelope.payload).let {
                    require(isUUID(it.transferId))
                    require(it.size >= 0 && it.size <= 9_007_199_254_740_991L)
                    require(it.mimeType.isNotBlank())
                    require(it.fileName.isNotBlank() && it.fileName !in listOf(".", ".."))
                    require(it.fileName.none { c -> c == '/' || c == '\\' || c.isISOControl() })
                    require(it.sha256.matches(Regex("[a-f0-9]{64}"))) { "Invalid SHA-256" }
                }
            MessageType.FILE_ACCEPT ->
                json.decodeFromJsonElement<FileAccept>(envelope.payload).let {
                    require(
                        isUUID(it.transferId) &&
                            it.offset >= 0 &&
                            it.offset <= 9_007_199_254_740_991L
                    )
                }
            MessageType.FILE_COMPLETE ->
                json.decodeFromJsonElement<FileComplete>(envelope.payload).let {
                    require(isUUID(it.transferId) && it.sha256.matches(Regex("[a-f0-9]{64}")))
                }
            MessageType.FILE_CANCEL ->
                json.decodeFromJsonElement<FileCancel>(envelope.payload).let {
                    require(isUUID(it.transferId) && (it.reason?.length ?: 0) <= 256)
                }
            MessageType.DEVICE_COMMAND ->
                json.decodeFromJsonElement<DeviceCommand>(envelope.payload).validate()
            MessageType.COMMAND_RESULT ->
                json.decodeFromJsonElement<CommandResult>(envelope.payload).let {
                    require(
                        isUUID(it.requestId) &&
                            it.message.isNotEmpty() &&
                            it.message.length <= 256 &&
                            (it.success || it.data == null)
                    )
                    it.data?.validate()
                }
            MessageType.DEVICE_STATUS ->
                json.decodeFromJsonElement<DeviceStatus>(envelope.payload).let {
                    it.call?.validate()
                    require(it.batteryPercent == null || it.batteryPercent in 0..100)
                    require(
                        (it.mediaTitle?.length ?: 0) <= 512 && (it.mediaArtist?.length ?: 0) <= 512
                    )
                }
            MessageType.TEXT_SHARED ->
                json.decodeFromJsonElement<SharedText>(envelope.payload).let {
                    require(it.text.isNotEmpty() && it.text.length <= 16_384)
                }
        }
    }

    private fun isUUID(value: String): Boolean =
        value.matches(
            Regex("[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}")
        )
}
