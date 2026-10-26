package dev.androfest.android.features.notifications

import android.content.Context
import dev.androfest.android.core.device.DeviceIdentity
import dev.androfest.protocol.DeviceCommand
import dev.androfest.protocol.MessageType
import dev.androfest.protocol.NotificationPosted
import dev.androfest.protocol.NotificationRemoved
import dev.androfest.protocol.WireCodec
import dev.androfest.protocol.WireEnvelope
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

class NotificationRepository(context: Context, private val identity: DeviceIdentity) {
    // Installed only while the OS notification listener is alive; called on Main.
    var actionHandler: ((DeviceCommand) -> String)? = null
    var refreshHandler: (() -> Unit)? = null
    private val _testReply = MutableStateFlow<String?>(null)
    val testReply = _testReply.asStateFlow()

    fun recordTestReply(text: String) {
        _testReply.value = text.take(4096)
    }

    @Volatile private var ownNotificationTest = false
    val isCapturing: Boolean
        get() = _captureEnabled.value || ownNotificationTest

    fun permitsPackage(packageName: String): Boolean =
        isCapturing && (!ownNotificationTest || packageName == "dev.androfest.android")

    fun setOwnNotificationTest(enabled: Boolean) {
        if (dev.androfest.android.BuildConfig.DEBUG) ownNotificationTest = enabled
    }

    private val preferences = context.getSharedPreferences("notifications", Context.MODE_PRIVATE)
    private val _captureEnabled = MutableStateFlow(preferences.getBoolean("captureEnabled", false))
    val captureEnabled = _captureEnabled.asStateFlow()
    private val _hidePersistent = MutableStateFlow(preferences.getBoolean("hidePersistent", true))
    val hidePersistent = _hidePersistent.asStateFlow()
    private val _hideLocked = MutableStateFlow(preferences.getBoolean("hideLocked", false))
    val hideLocked = _hideLocked.asStateFlow()

    fun setHideLocked(hidden: Boolean) {
        preferences.edit().putBoolean("hideLocked", hidden).apply()
        _hideLocked.value = hidden
    }

    private val _excludedPackages =
        MutableStateFlow(preferences.getStringSet("excludedPackages", emptySet()).orEmpty().toSet())
    val excludedPackages = _excludedPackages.asStateFlow()
    private val _applications = MutableStateFlow<Map<String, String>>(emptyMap())
    val applications = _applications.asStateFlow()

    fun observeApplication(packageName: String, name: String) {
        _applications.update { current ->
            (current + (packageName to name)).entries.toList().takeLast(64).associate {
                it.toPair()
            }
        }
    }

    fun setHidePersistent(hidden: Boolean) {
        preferences.edit().putBoolean("hidePersistent", hidden).apply()
        _hidePersistent.value = hidden
    }

    fun setApplicationEnabled(packageName: String, enabled: Boolean) {
        val updated =
            if (enabled) _excludedPackages.value - packageName
            else _excludedPackages.value + packageName
        preferences.edit().putStringSet("excludedPackages", updated).apply()
        _excludedPackages.value = updated
    }

    private val _listenerConnected = MutableStateFlow(false)
    val listenerConnected = _listenerConnected.asStateFlow()
    private val _events = MutableStateFlow<List<WireEnvelope>>(emptyList())
    val events = _events.asStateFlow()
    private val _outbound =
        MutableSharedFlow<WireEnvelope>(
            extraBufferCapacity = 64,
            onBufferOverflow = BufferOverflow.DROP_OLDEST,
        )
    val outbound = _outbound.asSharedFlow()

    fun setCaptureEnabled(enabled: Boolean) {
        preferences.edit().putBoolean("captureEnabled", enabled).apply()
        _captureEnabled.value = enabled
        if (!enabled) clear()
    }

    fun setListenerConnected(connected: Boolean) {
        _listenerConnected.value = connected
    }

    fun posted(notification: NotificationPosted) = record {
        WireCodec.message(MessageType.NOTIFICATION_POSTED, identity.id, notification)
    }

    fun removed(key: String) = record {
        WireCodec.message(MessageType.NOTIFICATION_REMOVED, identity.id, NotificationRemoved(key))
    }

    fun withdraw(keys: Collection<String>) {
        keys.take(64).forEach { key ->
            _outbound.tryEmit(
                WireCodec.message(
                    MessageType.NOTIFICATION_REMOVED,
                    identity.id,
                    NotificationRemoved(key),
                )
            )
        }
    }

    fun clear() {
        _events.value = emptyList()
    }

    private fun record(create: () -> WireEnvelope) {
        if (!isCapturing) return
        // Oversized or malformed notifications are ignored. Contents never enter logs or disk.
        val event = runCatching { create().also { WireCodec.encode(it) } }.getOrNull() ?: return
        _events.update { (listOf(event) + it).take(30) }
        _outbound.tryEmit(event)
    }
}
