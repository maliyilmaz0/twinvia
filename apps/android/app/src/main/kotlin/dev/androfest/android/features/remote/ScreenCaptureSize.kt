package dev.androfest.android.features.remote

import dev.twinvia.protocol.RemoteScreen
import kotlin.math.sqrt

/** Bounds captures by both the selected long edge and the receiving protocol's pixel budget. */
internal data class ScreenCaptureSize(val width: Int, val height: Int) {
    companion object {
        fun fit(width: Int, height: Int, detail: Boolean): ScreenCaptureSize {
            require(width > 0 && height > 0)
            val edge = if (detail) 2160.0 else 480.0
            val scale =
                minOf(
                    1.0,
                    edge / maxOf(width, height),
                    sqrt(RemoteScreen.MAX_PIXELS / (width.toDouble() * height)),
                )
            return ScreenCaptureSize(
                maxOf(1, (width * scale).toInt()),
                maxOf(1, (height * scale).toInt()),
            )
        }
    }
}
