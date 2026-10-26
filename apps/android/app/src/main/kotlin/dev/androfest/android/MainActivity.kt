package dev.androfest.android

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModelProvider
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import dev.androfest.android.core.connection.BridgeConnectionService
import dev.androfest.android.features.dashboard.DashboardScreen
import dev.androfest.android.features.dashboard.DashboardViewModel
import dev.androfest.android.features.notifications.NotificationTestReplyReceiver

class MainActivity : ComponentActivity() {
    private val model by lazy { ViewModelProvider(this)[DashboardViewModel::class.java] }
    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) {
            if (it) postTestNotification()
        }
    private val nearbyWifiPermission =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            if (granted.values.any { !it })
                model.showNotice("Allow Nearby Devices permission for Bluetooth.")
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val nearbyPermissions =
            arrayOf(
                Manifest.permission.NEARBY_WIFI_DEVICES,
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
            )
        if (nearbyPermissions.any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED })
            nearbyWifiPermission.launch(nearbyPermissions)
        if (savedInstanceState == null) {
            receiveShare(intent)
            receiveDebugCommand(intent)
        }
        setContent { DashboardScreen(model, ::requestTestNotification, ::scanMac) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent)
        receiveDebugCommand(intent)
    }

    override fun onStart() {
        super.onStart()
        // Start while this activity is visible; Android restricts background FGS starts.
        ContextCompat.startForegroundService(
            this,
            Intent(this, BridgeConnectionService::class.java),
        )
    }

    private fun scanMac() {
        val options =
            GmsBarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                .enableAutoZoom()
                .build()
        GmsBarcodeScanning.getClient(this, options)
            .startScan()
            .addOnSuccessListener { barcode -> barcode.rawValue?.let(model::pair) }
            .addOnFailureListener { error ->
                if (error !is ApiException || error.statusCode != CommonStatusCodes.CANCELED) {
                    model.showNotice(
                        "Could not open the QR scanner. Update Google Play services and try again."
                    )
                }
            }
    }

    private fun receiveDebugCommand(intent: Intent) {
        if (!BuildConfig.DEBUG) return
        if (intent.getBooleanExtra("dev.androfest.DEBUG_PAIR_FROM_FILE", false)) {
            val file = java.io.File(filesDir, "debug-pairing-invitation.txt")
            val link =
                runCatching {
                        require(file.length() in 1..4096)
                        file.readText()
                    }
                    .getOrNull()
            file.delete()
            link?.let(model::pair)
        }
        if (intent.getBooleanExtra("dev.androfest.DEBUG_TEST_CONNECTION", false))
            model.bridge.sendTest()
        if (intent.getBooleanExtra("dev.androfest.DEBUG_RETRY_NATIVE", false))
            model.bridge.retryConnection()
        if (intent.getBooleanExtra("dev.androfest.DEBUG_FORGET_CONNECTION", false)) {
            model.notifications.setOwnNotificationTest(false)
            model.bridge.forget()
        }
        if (intent.getBooleanExtra("dev.androfest.DEBUG_SYSTEM_NOTIFICATION_TEST", false)) {
            model.notifications.setOwnNotificationTest(true)
            requestTestNotification()
        }
    }

    private fun receiveShare(intent: Intent) {
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.let {
                model.receiveSharedText(it)
            }
        }
        val uris =
            when (intent.action) {
                Intent.ACTION_SEND ->
                    listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
                Intent.ACTION_SEND_MULTIPLE ->
                    intent
                        .getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                        .orEmpty()
                else -> emptyList()
            }
        model.selectFiles(uris, persist = false)
    }

    private fun requestTestNotification() {
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else postTestNotification()
    }

    private fun postTestNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                "bridge-test",
                "Connection tests",
                NotificationManager.IMPORTANCE_DEFAULT,
            )
        )
        manager.notify(
            1001,
            NotificationCompat.Builder(this, "bridge-test")
                .setSmallIcon(dev.androfest.android.R.drawable.ic_launcher)
                .setContentTitle("Twinvia ready")
                .setContentText(
                    "This notification appears in the app when notification access and local capture are enabled."
                )
                .addAction(
                    NotificationCompat.Action.Builder(
                            0,
                            "Test reply",
                            PendingIntent.getBroadcast(
                                this,
                                1001,
                                Intent(this, NotificationTestReplyReceiver::class.java),
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                            ),
                        )
                        .addRemoteInput(
                            RemoteInput.Builder("demo-reply").setLabel("Your test reply").build()
                        )
                        .build()
                )
                .setAutoCancel(true)
                .build(),
        )
    }
}
