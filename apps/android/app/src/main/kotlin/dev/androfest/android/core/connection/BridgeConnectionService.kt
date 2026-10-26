package dev.androfest.android.core.connection

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import dev.androfest.android.AndrofestApplication
import dev.androfest.android.MainActivity
import dev.androfest.android.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/** Keeps the shared bridge alive when the dashboard leaves the foreground. */
class BridgeConnectionService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                    CHANNEL_ID,
                    "Device connection",
                    NotificationManager.IMPORTANCE_LOW,
                )
                .apply { description = "Keeps the Mac connection active in the background." }
        )
        val bridge = (application as AndrofestApplication).bridge
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification(bridge.status.value),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        scope.launch {
            combine(bridge.status, bridge.files.incoming, bridge.features.ringing) {
                    status,
                    incoming,
                    ringing ->
                    when {
                        incoming != null -> "Incoming file: ${incoming.fileName} · Open to accept"
                        ringing -> "Mac is ringing your phone · Open to stop"
                        else -> status
                    }
                }
                .collect { manager.notify(NOTIFICATION_ID, notification(it)) }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun notification(status: String): Notification {
        val open =
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher)
            .setContentTitle("Twinvia connection active")
            .setContentText(status)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "bridge-connection"
        private const val NOTIFICATION_ID = 1002
    }
}
