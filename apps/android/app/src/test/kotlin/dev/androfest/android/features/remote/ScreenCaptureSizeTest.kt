package dev.androfest.android.features.remote

import dev.twinvia.protocol.RemoteScreen
import org.junit.Assert.*
import org.junit.Test

class ScreenCaptureSizeTest {
    @Test
    fun nearSquareDetailFramesFitTheReceivingProtocol() {
        for ((width, height) in listOf(2076 to 2152, 2152 to 2076, 2160 to 2160, 4096 to 4096)) {
            val size = ScreenCaptureSize.fit(width, height, detail = true)
            assertTrue(size.width.toLong() * size.height <= RemoteScreen.MAX_PIXELS)
            assertTrue(maxOf(size.width, size.height) <= 2160)
            assertTrue(size.width <= width && size.height <= height)
            assertEquals(width.toDouble() / height, size.width.toDouble() / size.height, 0.002)
            RemoteScreen("AA==", size.width, size.height).validate()
        }
        assertEquals(ScreenCaptureSize(2048, 2048), ScreenCaptureSize.fit(2160, 2160, true))
    }

    @Test
    fun responsivePortraitAndSmallImagesKeepTheirExistingSizes() {
        assertEquals(ScreenCaptureSize(996, 2160), ScreenCaptureSize.fit(1080, 2340, true))
        assertEquals(ScreenCaptureSize(221, 480), ScreenCaptureSize.fit(1080, 2340, false))
        assertEquals(ScreenCaptureSize(200, 300), ScreenCaptureSize.fit(200, 300, true))
        assertEquals(ScreenCaptureSize(2048, 2048), ScreenCaptureSize.fit(2048, 2048, true))
    }

    @Test
    fun largeDimensionsCannotOverflowAndInvalidDimensionsAreRejected() {
        for ((width, height) in listOf(Int.MAX_VALUE to Int.MAX_VALUE, 1 to Int.MAX_VALUE)) {
            val size = ScreenCaptureSize.fit(width, height, true)
            RemoteScreen("AA==", size.width, size.height).validate()
        }
        assertThrows(IllegalArgumentException::class.java) { ScreenCaptureSize.fit(0, 1080, true) }
        assertThrows(IllegalArgumentException::class.java) { ScreenCaptureSize.fit(1080, -1, true) }
    }
}
