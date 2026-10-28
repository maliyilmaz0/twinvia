package dev.androfest.android

import android.app.Application
import dev.androfest.android.core.connection.BridgeRepository
import dev.androfest.android.core.device.DeviceIdentity
import dev.androfest.android.features.notifications.NotificationRepository
import dev.androfest.android.features.remote.RemoteControlSession

class TwinviaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // The lease is process-local; remove a notification left behind after a process crash.
        RemoteControlSession.stop(this)
    }

    val deviceIdentity by lazy { DeviceIdentity(this) }
    val notifications by lazy { NotificationRepository(this, deviceIdentity) }
    val bridge by lazy { BridgeRepository(this, deviceIdentity, notifications) }
}
