package dev.androfest.android.core.device

import android.content.Context
import android.os.Build
import dev.twinvia.protocol.DeviceHello
import java.util.UUID

class DeviceIdentity(context: Context) {
    private val preferences = context.getSharedPreferences("device", Context.MODE_PRIVATE)
    val id: String =
        preferences.getString("id", null)
            ?: UUID.randomUUID().toString().also {
                preferences.edit().putString("id", it).apply()
            }
    val name: String = Build.MODEL

    fun hello() =
        DeviceHello(
            name = name,
            platform = "android",
            osVersion = Build.VERSION.RELEASE,
            // Advertise remote capabilities only after an authenticated transport implements them.
            capabilities = emptyList(),
        )
}
