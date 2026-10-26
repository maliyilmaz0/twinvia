package dev.androfest.android

import android.app.Application
import dev.androfest.android.core.connection.BridgeRepository
import dev.androfest.android.core.device.DeviceIdentity
import dev.androfest.android.features.notifications.NotificationRepository

class TwinviaApplication : Application() {
    val deviceIdentity by lazy { DeviceIdentity(this) }
    val notifications by lazy { NotificationRepository(this, deviceIdentity) }
    val bridge by lazy { BridgeRepository(this, deviceIdentity, notifications) }
}
