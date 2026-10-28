package dev.androfest.android.features.remote

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.view.Display
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import dev.twinvia.protocol.RemoteScreen
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout

/**
 * No event content is read. The service only handles phone-approved screenshot and gesture
 * requests.
 */
class RemoteAccessibilityService : AccessibilityService() {
    companion object {
        @Volatile
        var current: RemoteAccessibilityService? = null
            private set
    }

    override fun onServiceConnected() {
        current = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        current = null
        RemoteControlSession.stop(this)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        current = null
        RemoteControlSession.stop(this)
        super.onDestroy()
    }

    suspend fun snapshot(): RemoteScreen =
        withTimeout(8_000) {
            val result =
                suspendCancellableCoroutine<ScreenshotResult> { continuation ->
                    takeScreenshot(
                        Display.DEFAULT_DISPLAY,
                        mainExecutor,
                        object : TakeScreenshotCallback {
                            override fun onSuccess(result: ScreenshotResult) {
                                if (continuation.isActive) continuation.resume(result)
                            }

                            override fun onFailure(errorCode: Int) {
                                if (continuation.isActive)
                                    continuation.resumeWithException(
                                        IllegalStateException(
                                            "Screen capture unavailable ($errorCode)."
                                        )
                                    )
                            }
                        },
                    )
                }
            val buffer = result.hardwareBuffer
            try {
                val hardware =
                    Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                        ?: error("Could not read the phone screen.")
                val width = hardware.width
                val height = hardware.height
                val scale = minOf(1.0, 480.0 / maxOf(width, height))
                val targetWidth = maxOf(1, (width * scale).toInt())
                val targetHeight = maxOf(1, (height * scale).toInt())
                val software = hardware.copy(Bitmap.Config.ARGB_8888, false)
                val small = Bitmap.createScaledBitmap(software, targetWidth, targetHeight, true)
                try {
                    var bytes = ByteArray(0)
                    for (quality in listOf(50, 35, 20)) {
                        val output = ByteArrayOutputStream()
                        small.compress(Bitmap.CompressFormat.JPEG, quality, output)
                        bytes = output.toByteArray()
                        if (bytes.size <= 70_000) break
                    }
                    check(bytes.size <= 70_000) {
                        "Screen image exceeds the Bluetooth transfer limit."
                    }
                    RemoteScreen(
                        Base64.getEncoder().encodeToString(bytes),
                        targetWidth,
                        targetHeight,
                    )
                } finally {
                    small.recycle()
                    if (small !== software) software.recycle()
                }
            } finally {
                buffer.close()
            }
        }

    suspend fun tap(x: Int, y: Int) =
        withTimeout(5_000) {
            val bounds = getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
            val px = bounds.left + x * bounds.width() / 10_000f
            val py = bounds.top + y * bounds.height() / 10_000f
            val path = Path().apply { moveTo(px, py) }
            val gesture =
                GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, 80))
                    .build()
            performGesture(gesture)
        }

    suspend fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Int) =
        withTimeout(5_000) {
            val bounds = getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
            val path =
                Path().apply {
                    moveTo(
                        bounds.left + x1 * bounds.width() / 10_000f,
                        bounds.top + y1 * bounds.height() / 10_000f,
                    )
                    lineTo(
                        bounds.left + x2 * bounds.width() / 10_000f,
                        bounds.top + y2 * bounds.height() / 10_000f,
                    )
                }
            val gesture =
                GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs.toLong()))
                    .build()
            performGesture(gesture)
        }

    private suspend fun performGesture(gesture: GestureDescription) {
        suspendCancellableCoroutine<Unit> { continuation ->
            val accepted =
                dispatchGesture(
                    gesture,
                    object : GestureResultCallback() {
                        override fun onCompleted(gestureDescription: GestureDescription?) {
                            if (continuation.isActive) continuation.resume(Unit)
                        }

                        override fun onCancelled(gestureDescription: GestureDescription?) {
                            if (continuation.isActive)
                                continuation.resumeWithException(
                                    IllegalStateException("Touch was interrupted on the phone.")
                                )
                        }
                    },
                    Handler(Looper.getMainLooper()),
                )
            if (!accepted && continuation.isActive)
                continuation.resumeWithException(IllegalStateException("Phone rejected the touch."))
        }
    }
}
