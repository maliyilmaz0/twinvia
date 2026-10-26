package dev.androfest.android.features.calls

import android.Manifest
import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.telecom.TelecomManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import dev.androfest.android.R
import dev.androfest.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Phone-local consent UI. Never answers or captures audio merely on call-state changes. */
class PhoneCallHandoff(private val context: Context, scope: CoroutineScope) {
    private val machine = CallHandoffState()
    private val _state = MutableStateFlow(machine.snapshot)
    val state = _state.asStateFlow()
    private var offeredToken: String? = null
    private var notificationUpdates = 0
    private var dismissedToken: String? = null
    private var listener: TelephonyCallback? = null
    @Volatile private var connected = false
    var onChanged: (() -> Unit)? = null
    private val permissionGranted: Boolean
        get() =
            context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
                PackageManager.PERMISSION_GRANTED

    val available: Boolean
        get() = permissionGranted && listener != null

    private val callback =
        object : TelephonyCallback(), TelephonyCallback.CallStateListener {
            override fun onCallStateChanged(callState: Int) {
                val next =
                    when (callState) {
                        TelephonyManager.CALL_STATE_RINGING -> "ringing"
                        TelephonyManager.CALL_STATE_OFFHOOK -> "active"
                        else -> "idle"
                    }
                if (machine.transition(next)) {
                    publish()
                    updateNotification(alert = true)
                }
            }
        }

    init {
        context
            .getSystemService(NotificationManager::class.java)
            .createNotificationChannel(
                NotificationChannel(CHANNEL, "Call handoff", NotificationManager.IMPORTANCE_HIGH)
                    .apply {
                        description = "Approve call audio handoff to a supported Mac audio path."
                        lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                    }
            )
        scope.launch(Dispatchers.Main.immediate) {
            while (isActive) {
                refreshPermission()
                delay(2000)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun refreshPermission() {
        val manager = context.getSystemService(TelephonyManager::class.java)
        if (permissionGranted && listener == null)
            runCatching {
                manager.registerTelephonyCallback(context.mainExecutor, callback)
                listener = callback
                publish()
            }
        else if (!permissionGranted && listener != null) {
            runCatching { manager.unregisterTelephonyCallback(callback) }
            listener = null
            machine.transition("idle")
            publish()
            updateNotification(false)
        }
    }

    fun setConnected(value: Boolean) {
        context.mainExecutor.execute {
            if (connected != value) {
                connected = value
                updateNotification(false)
            }
            diagnostics()
        }
    }

    fun status(): PhoneCallState? =
        if (!available || listener == null) null
        else machine.snapshot.let { PhoneCallState(it.state, it.token, it.approval) }

    private fun publish() {
        _state.value = machine.snapshot
        onChanged?.invoke()
        diagnostics()
    }

    @SuppressLint("MissingPermission")
    private fun updateNotification(alert: Boolean) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val call = machine.snapshot
        if (
            call.state == "idle" ||
                call.token == dismissedToken ||
                (!connected && offeredToken != call.token)
        ) {
            manager.cancel(NOTIFICATION_ID)
            return
        }
        offeredToken = call.token
        val intent =
            Intent(context, CallHandoffActivity::class.java)
                .putExtra("callToken", call.token)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open =
            PendingIntent.getActivity(
                context,
                NOTIFICATION_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        manager.notify(
            NOTIFICATION_ID,
            NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_launcher)
                .setContentTitle(
                    if (call.approval != null) "Mac handoff approved"
                    else if (call.state == "ringing") "Manage incoming call on Mac"
                    else "Request Mac audio handoff?"
                )
                .setContentText(
                    if (connected) "Open transfer options" else "Waiting for Mac connection"
                )
                .setContentIntent(open)
                .addAction(0, "Transfer options", open)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setOnlyAlertOnce(!alert || !connected)
                .setAutoCancel(false)
                .setOngoing(false)
                .build(),
        )
        notificationUpdates++
        diagnostics()
    }

    fun approve(token: String) {
        check(connected) { "Wait for the Mac connection first" }
        dismissedToken = null
        machine.approve(token)
        publish()
        updateNotification(false)
    }

    fun decline(token: String) {
        dismissedToken = token
        machine.revoke(token)
        publish()
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    fun revokeApproval() {
        dismissedToken = machine.snapshot.token
        machine.revoke()
        publish()
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    fun execute(command: DeviceCommand): String {
        val call = machine.snapshot
        check(connected && call.token == command.actionToken && call.state != "idle") {
            "This call is no longer valid"
        }
        when (command.action) {
            DeviceAction.CALL_ANSWER_MAC -> {
                check(
                    context.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) ==
                        PackageManager.PERMISSION_GRANTED
                ) {
                    "Allow answering calls on your phone"
                }
                if (call.state == "ringing")
                    context.getSystemService(TelecomManager::class.java).acceptRingingCall()
                approve(call.token!!)
                return "Mac audio relay approved"
            }
            DeviceAction.CALL_HANDOFF_APPROVE -> {
                approve(call.token!!)
                return "Mac audio relay approved"
            }
            DeviceAction.CALL_END -> {
                check(
                    context.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) ==
                        PackageManager.PERMISSION_GRANTED
                ) {
                    "Allow answering calls on your phone"
                }
                check(context.getSystemService(TelecomManager::class.java).endCall()) {
                    "Could not end the call"
                }
                return "Call ended"
            }
            else -> error("Invalid call command")
        }
    }

    private fun diagnostics() {
        if (dev.androfest.android.BuildConfig.DEBUG)
            runCatching {
                java.io
                    .File(context.filesDir, "call-handoff-status.json")
                    .writeText(
                        org.json
                            .JSONObject()
                            .put("permissionGranted", permissionGranted)
                            .put("registered", listener != null)
                            .put("connected", connected)
                            .put("state", machine.snapshot.state)
                            .put("approved", machine.snapshot.approval != null)
                            .put("notificationUpdates", notificationUpdates)
                            .toString()
                    )
            }
    }

    companion object {
        const val CHANNEL = "call-handoff"
        const val NOTIFICATION_ID = 1108
        val actions =
            setOf(
                DeviceAction.CALL_ANSWER_MAC,
                DeviceAction.CALL_HANDOFF_APPROVE,
                DeviceAction.CALL_END,
            )
    }
}
