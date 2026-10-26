package dev.androfest.protocol

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class ClipboardImageTest {
    private val id = UUID.fromString("f0012345-6789-4abc-8def-0123456789ab")
    private val data = ByteArray(100_000) { (it % 251).toByte() }

    private fun frame(offset: Int, total: Int = data.size): ClipboardImageChunk {
        val bytes = data.copyOfRange(offset, minOf(offset + 65_536, data.size))
        val frame =
            ByteBuffer.allocate(60 + bytes.size)
                .putInt(0x41434931)
                .putLong(id.mostSignificantBits)
                .putLong(id.leastSignificantBits)
                .putInt(offset)
                .putInt(total)
                .put(MessageDigest.getInstance("SHA-256").digest(data))
                .put(bytes)
                .array()
        return ClipboardImageChunk.decode(frame)
    }

    @Test
    fun orderedChunksVerifyHashAndReleaseAssembly() {
        val receiver = ClipboardImageAssembler()
        assertNull(receiver.accept(frame(0), 0))
        assertArrayEquals(data, receiver.accept(frame(65_536), 10))
        assertNull(receiver.accept(frame(0), 11))
    }

    @Test
    fun corruptionReorderingOversizeAndTimeoutAreRejected() {
        val receiver = ClipboardImageAssembler()
        receiver.accept(frame(0), 0)
        assertThrows(IllegalArgumentException::class.java) { receiver.accept(frame(0), 1) }
        receiver.reset()
        receiver.accept(frame(0), 0)
        val bad = frame(65_536)
        bad.data[0] = (bad.data[0].toInt() xor 1).toByte()
        assertThrows(IllegalArgumentException::class.java) { receiver.accept(bad, 2) }
        assertThrows(IllegalArgumentException::class.java) { frame(0, 20 * 1024 * 1024 + 1) }
        receiver.accept(frame(0), 0)
        assertThrows(IllegalArgumentException::class.java) {
            receiver.accept(frame(65_536), 15_001)
        }
    }
}
