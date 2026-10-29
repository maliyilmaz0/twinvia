package dev.androfest.android.features.remote

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** A phone-approved, process-local lease. Pairing and transport authentication remain mandatory. */
object RemoteControlSession {
    private const val CHANNEL = "twinvia-remote-control"
    private const val NOTIFICATION = 4104
    private const val LEASE_MS = 5 * 60 * 1000L
    private var until = 0L
    private var generation = 0L
    private var screenOffReceiver: BroadcastReceiver? = null
    private val _active = MutableStateFlow(false)
    val active = _active.asStateFlow()
    private val _control = MutableStateFlow(false)
    val control = _control.asStateFlow()

    @Synchronized
    fun start(context: Context) {
        val app = context.applicationContext
        check(RemoteAccessibilityService.current != null) {
            "Enable Twinvia screen control in Android Accessibility settings first."
        }
        if (Build.VERSION.SDK_INT >= 33)
            check(
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
            ) {
                "Allow notifications so the phone can show the active remote session."
            }
        until = SystemClock.elapsedRealtime() + LEASE_MS
        showNotification(app, false)
        screenOffReceiver?.let { runCatching { app.unregisterReceiver(it) } }
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    stop(context)
                }
            }
        app.registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
        screenOffReceiver = receiver
        val lease = ++generation
        Handler(Looper.getMainLooper())
            .postDelayed({ if (generation == lease) stop(app) }, LEASE_MS)
        _control.value = false
        _active.value = true
    }

    @Synchronized
    fun enableControl(context: Context) {
        requireActive(context)
        showNotification(context.applicationContext, true)
        _control.value = true
    }

    private fun showNotification(app: Context, control: Boolean) {
        val manager = app.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL,
                "Twinvia screen control",
                NotificationManager.IMPORTANCE_LOW,
            )
        )
        val stop =
            PendingIntent.getBroadcast(
                app,
                0,
                Intent(app, StopRemoteControlReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val notification =
            NotificationCompat.Builder(app, CHANNEL)
                .setSmallIcon(dev.androfest.android.R.mipmap.ic_launcher)
                .setContentTitle(
                    if (control) "Twinvia screen viewing and control" else "Twinvia screen viewing"
                )
                .setContentText(
                    if (control) "Your paired Mac can view and touch this screen."
                    else "Your paired Mac can view this screen."
                )
                .setOngoing(true)
                .setTimeoutAfter(
                    maxOf(1L, if (until == 0L) LEASE_MS else until - SystemClock.elapsedRealtime())
                )
                .addAction(0, "Stop sharing", stop)
                .build()
        manager.notify(NOTIFICATION, notification)
    }

    @Synchronized
    fun requireActive(context: Context) {
        if (until <= SystemClock.elapsedRealtime()) stop(context)
        check(_active.value && RemoteAccessibilityService.current != null) {
            "Start screen control on your phone first."
        }
        if (context.getSystemService(android.app.KeyguardManager::class.java).isDeviceLocked) {
            stop(context)
            error("Unlock your phone and start a new screen-control session.")
        }
    }

    @Synchronized
    fun requireControlActive(context: Context) {
        requireActive(context)
        check(_control.value) { "Enable touch control separately on your phone." }
    }

    @Synchronized
    fun stop(context: Context) {
        FastScreenServer.stop()
        generation++
        until = 0L
        _active.value = false
        _control.value = false
        val app = context.applicationContext
        screenOffReceiver?.let { runCatching { app.unregisterReceiver(it) } }
        screenOffReceiver = null
        app.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION)
    }
}

class StopRemoteControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        RemoteControlSession.stop(context)
    }
}
