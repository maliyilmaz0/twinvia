package dev.androfest.android.features.notifications

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.LruCache
import java.io.ByteArrayOutputStream
import java.util.Base64

class NotificationIcon(private val context: Context) {
    private val cache = LruCache<String, String>(64)

    fun png(packageName: String): String? =
        cache[packageName]
            ?: runCatching {
                    val drawable = context.packageManager.getApplicationIcon(packageName)
                    val bitmap = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
                    try {
                        drawable.setBounds(0, 0, 96, 96)
                        drawable.draw(Canvas(bitmap))
                        val output = ByteArrayOutputStream()
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                        val bytes = output.toByteArray()
                        check(bytes.size <= 65_536)
                        Base64.getEncoder().encodeToString(bytes).also {
                            cache.put(packageName, it)
                        }
                    } finally {
                        bitmap.recycle()
                    }
                }
                .getOrNull()
}
