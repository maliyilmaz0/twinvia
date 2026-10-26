package dev.androfest.android.features.notifications

import android.app.KeyguardManager
import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import dev.androfest.android.AndrofestApplication
import dev.androfest.android.core.connection.BridgeConnectionService
import dev.androfest.protocol.DeviceAction
import dev.androfest.protocol.DeviceCommand
import dev.androfest.protocol.NotificationPosted
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.combine

class BridgeNotificationListener : NotificationListenerService() {
    private val repository
        get() = (application as AndrofestApplication).notifications

    private val bridge
        get() = (application as AndrofestApplication).bridge

    private val icons by lazy { NotificationIcon(this) }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val removedKeys = linkedSetOf<String>()
    private var connected = false

    private data class ActionSnapshot(val token: String, val postedAt: Long)

    private val actions = linkedMapOf<String, ActionSnapshot>()

    override fun onCreate() {
        super.onCreate()
        repository.actionHandler = ::performAction
        repository.refreshHandler = ::refreshNotifications
        scope.launch {
            combine(
                    repository.hidePersistent,
                    repository.excludedPackages,
                    repository.captureEnabled,
                    repository.hideLocked,
                    bridge.connected,
                ) { _, _, _, _, linked ->
                    linked
                }
                .collect { linked ->
                    if (!linked) {
                        removedKeys.clear()
                    } else if (connected) refreshNotifications()
                }
        }
    }

    override fun onDestroy() {
        repository.actionHandler = null
        repository.refreshHandler = null
        repository.withdraw(actions.keys.toList())
        actions.clear()
        scope.cancel()
        super.onDestroy()
    }

    override fun onListenerConnected() {
        connected = true
        repository.setListenerConnected(true)
        refreshNotifications()
    }

    override fun onListenerDisconnected() {
        connected = false
        repository.withdraw(actions.keys.toList())
        actions.clear()
        repository.setListenerConnected(false)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        emitNotification(sbn, replay = false)
    }

    private fun emitNotification(sbn: StatusBarNotification, replay: Boolean) {
        if (isConnectionStatus(sbn)) return
        if (!repository.permitsPackage(sbn.packageName)) return
        val notification = sbn.notification
        val appName =
            runCatching {
                    packageManager
                        .getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0))
                        .toString()
                }
                .getOrDefault(sbn.packageName)
        repository.observeApplication(sbn.packageName, appName)
        if (shouldHide(sbn)) {
            removeFiltered(sbn.key)
            return
        }
        removedKeys.remove(sbn.key)
        val redacted =
            repository.hideLocked.value &&
                getSystemService(KeyguardManager::class.java).isDeviceLocked
        val token =
            actions[sbn.key]?.takeIf { replay && it.postedAt == sbn.postTime }?.token
                ?: UUID.randomUUID().toString()
        actions[sbn.key] = ActionSnapshot(token, sbn.postTime)
        if (actions.size > 64) actions.remove(actions.keys.first())
        repository.posted(
            NotificationPosted(
                key = sbn.key,
                packageName = sbn.packageName,
                appName = appName,
                title =
                    if (redacted) "New notification"
                    else notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
                text =
                    if (redacted) null
                    else
                        (notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                                ?: notification.extras.getCharSequence(Notification.EXTRA_TEXT))
                            ?.toString(),
                postedAt = sbn.postTime,
                canReply =
                    !redacted &&
                        notification.actions?.any { action ->
                            action.remoteInputs?.any { it.allowFreeFormInput } == true
                        } == true,
                appIconPng = icons.png(sbn.packageName),
                actionToken = token,
                canDismiss = sbn.isClearable,
                isReplay = replay,
            )
        )
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (isConnectionStatus(sbn)) return
        if (repository.permitsPackage(sbn.packageName)) repository.removed(sbn.key)
        removedKeys.remove(sbn.key)
        actions.remove(sbn.key)
    }

    private fun performAction(command: DeviceCommand): String {
        check(connected && repository.isCapturing) { "Notification access or sharing is disabled." }
        val snapshot = actions[command.key] ?: error("This notification is no longer valid.")
        check(snapshot.token == command.actionToken) {
            "The notification changed; try again from the current notification."
        }
        val sbn =
            activeNotifications.orEmpty().firstOrNull { it.key == command.key }
                ?: error("The notification was removed on the phone.")
        check(
            snapshot.postedAt == sbn.postTime &&
                repository.permitsPackage(sbn.packageName) &&
                !shouldHide(sbn)
        ) {
            "The notification changed or the app filter is disabled."
        }
        if (command.action == DeviceAction.NOTIFICATION_DISMISS) {
            check(sbn.isClearable) { "This notification cannot be dismissed." }
            actions.remove(sbn.key)
            cancelNotification(sbn.key)
            return "Notification dismissal sent to the phone."
        }
        check(command.action == DeviceAction.NOTIFICATION_REPLY)
        check(!getSystemService(KeyguardManager::class.java).isDeviceLocked) {
            "Unlock your phone to reply."
        }
        val action =
            sbn.notification.actions?.firstOrNull {
                it.remoteInputs?.any { input -> input.allowFreeFormInput } == true
            } ?: error("This notification no longer supports quick reply.")
        val input = action.remoteInputs.first { it.allowFreeFormInput }
        val fillIn = Intent()
        RemoteInput.addResultsToIntent(
            arrayOf(input),
            fillIn,
            Bundle().apply { putCharSequence(input.resultKey, command.text) },
        )
        RemoteInput.setResultsSource(fillIn, RemoteInput.SOURCE_FREE_FORM_INPUT)
        actions.remove(
            sbn.key
        ) // A token can submit a reply only once, even before the app updates its notification.
        try {
            action.actionIntent.send(this, 0, fillIn)
        } catch (error: Exception) {
            onNotificationPosted(sbn)
            throw IllegalStateException(
                "Could not deliver reply to the app; try the current notification again.",
                error,
            )
        }
        return "Reply delivered to the app."
    }

    private fun isConnectionStatus(sbn: StatusBarNotification) =
        sbn.packageName == packageName &&
            sbn.notification.channelId in
                setOf(
                    BridgeConnectionService.CHANNEL_ID,
                    dev.androfest.android.features.calls.PhoneCallHandoff.CHANNEL,
                )

    private fun shouldHide(sbn: StatusBarNotification): Boolean {
        val notification = sbn.notification
        if (isConnectionStatus(sbn)) return true
        // Dedicated, stable cellular-call state owns these alerts. Duration updates
        // from the dialer must not create repeated generic Mac notifications.
        if (
            bridge.handoff.available &&
                notification.category == Notification.CATEGORY_CALL &&
                sbn.packageName in
                    setOf(
                        "com.samsung.android.incallui",
                        "com.samsung.android.dialer",
                        "com.android.incallui",
                        "com.google.android.dialer",
                        "com.android.server.telecom",
                        "com.samsung.android.app.telephonyui",
                    )
        )
            return true
        val title = notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val body =
            (notification.extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                    ?: notification.extras.getCharSequence(Notification.EXTRA_TEXT))
                ?.toString()
        return NotificationFilter.shouldHide(
            excluded = sbn.packageName in repository.excludedPackages.value,
            hidePersistent = repository.hidePersistent.value,
            groupSummary = notification.flags and Notification.FLAG_GROUP_SUMMARY != 0,
            hasContent = !title.isNullOrBlank() || !body.isNullOrBlank(),
            ongoing = sbn.isOngoing,
            clearable = sbn.isClearable,
            foregroundService = notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0,
            category = notification.category,
        )
    }

    private fun cleanFilteredNotifications() {
        // Withdraw stale service/status rows from an already connected Mac as well.
        runCatching {
            activeNotifications.orEmpty().filter(::shouldHide).forEach { removeFiltered(it.key) }
        }
    }

    private fun refreshNotifications() {
        val previous = actions.keys.toList()
        if (!repository.isCapturing) {
            repository.withdraw(previous)
            actions.clear()
            return
        }
        if (
            repository.hideLocked.value &&
                getSystemService(KeyguardManager::class.java).isDeviceLocked
        ) {
            repository.withdraw(previous)
            actions.clear()
            return
        }
        cleanFilteredNotifications()
        runCatching {
            activeNotifications.orEmpty().takeLast(50).forEach {
                emitNotification(it, replay = true)
            }
        }
    }

    private fun removeFiltered(key: String) {
        actions.remove(key)
        if (!repository.isCapturing || !bridge.connected.value || !removedKeys.add(key)) return
        if (removedKeys.size > 512) removedKeys.remove(removedKeys.first())
        repository.removed(key)
    }
}
