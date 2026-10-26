package dev.twinvia.protocol

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

class WireFrameTest {
    @Test
    fun writesNetworkOrderAndReadsCoalescedFrames() {
        val output = ByteArrayOutputStream()
        WireFrame.write(output, byteArrayOf(1, 2, 3))
        WireFrame.write(output, byteArrayOf(4))
        val input = ByteArrayInputStream(output.toByteArray())
        assertArrayEquals(byteArrayOf(0, 0, 0, 3, 1, 2, 3), WireFrame.encode(byteArrayOf(1, 2, 3)))
        assertArrayEquals(byteArrayOf(1, 2, 3), WireFrame.read(input))
        assertArrayEquals(byteArrayOf(4), WireFrame.read(input))
    }

    @Test
    fun fragmentedInputIsReassembled() {
        val payload = ByteArray(1024) { it.toByte() }
        val bytes = ByteArrayInputStream(WireFrame.encode(payload))
        val fragmented =
            object : InputStream() {
                override fun read(): Int = bytes.read()
            }
        assertArrayEquals(payload, WireFrame.read(fragmented))
    }

    @Test
    fun invalidLengthsAndTruncationFailBeforeUse() {
        for (size in listOf(0, -1, WireCodec.MAX_MESSAGE_BYTES + 1, Int.MAX_VALUE)) {
            assertThrows(IllegalArgumentException::class.java) {
                WireFrame.read(ByteArrayInputStream(ByteBuffer.allocate(4).putInt(size).array()))
            }
        }
        assertThrows(IllegalArgumentException::class.java) { WireFrame.encode(byteArrayOf()) }
        assertThrows(IllegalArgumentException::class.java) {
            WireFrame.encode(ByteArray(WireCodec.MAX_MESSAGE_BYTES + 1))
        }
        assertThrows(EOFException::class.java) {
            WireFrame.read(ByteArrayInputStream(byteArrayOf(0, 0)))
        }
        assertThrows(EOFException::class.java) {
            WireFrame.read(ByteArrayInputStream(byteArrayOf(0, 0, 0, 2, 1)))
        }
    }
}
