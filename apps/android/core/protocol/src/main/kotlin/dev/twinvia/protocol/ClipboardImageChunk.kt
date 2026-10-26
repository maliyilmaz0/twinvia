package dev.twinvia.protocol

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/** Bounded, ordered image transfer inside the authenticated TLS session. */
data class ClipboardImageChunk(
    val id: String,
    val offset: Int,
    val total: Int,
    val sha256: ByteArray,
    val data: ByteArray,
) {
    companion object {
        const val MAX_IMAGE_BYTES = 20 * 1024 * 1024
        const val MAX_CHUNK_BYTES = 65_536

        fun decode(frame: ByteArray): ClipboardImageChunk {
            require(frame.size in 61..(60 + MAX_CHUNK_BYTES))
            val buffer = ByteBuffer.wrap(frame)
            require(buffer.int == 0x41434931)
            val id = UUID(buffer.long, buffer.long).toString()
            val offset = buffer.int
            val total = buffer.int
            require(total in 1..MAX_IMAGE_BYTES && offset in 0 until total)
            require(buffer.remaining() - 32 <= total - offset)
            val hash = ByteArray(32).also(buffer::get)
            return ClipboardImageChunk(
                id,
                offset,
                total,
                hash,
                ByteArray(buffer.remaining()).also(buffer::get),
            )
        }
    }
}

class ClipboardImageAssembler {
    private var id: String? = null
    private var buffer: ByteArray? = null
    private var hash = byteArrayOf()
    private var offset = 0
    private var started = 0L

    fun accept(chunk: ClipboardImageChunk, now: Long): ByteArray? {
        if (id == null || (chunk.offset == 0 && chunk.id != id) || now - started > 15_000) {
            reset()
            require(chunk.offset == 0)
            id = chunk.id
            buffer = ByteArray(chunk.total)
            hash = chunk.sha256
            started = now
        }
        val target = checkNotNull(buffer)
        require(
            chunk.id == id &&
                chunk.total == target.size &&
                chunk.offset == offset &&
                chunk.sha256.contentEquals(hash)
        )
        chunk.data.copyInto(target, offset)
        offset += chunk.data.size
        if (offset < target.size) return null
        val valid = MessageDigest.isEqual(MessageDigest.getInstance("SHA-256").digest(target), hash)
        reset()
        require(valid)
        return target
    }

    fun expire(now: Long) {
        if (id != null && now - started > 15_000) reset()
    }

    fun reset() {
        id = null
        buffer = null
        hash = byteArrayOf()
        offset = 0
        started = 0
    }
}
