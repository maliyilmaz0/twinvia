package dev.androfest.protocol

import java.nio.ByteBuffer
import java.util.UUID

data class FileChunk(val transferId: String, val offset: Long, val data: ByteArray) {
    fun encode(): ByteArray {
        val id = UUID.fromString(transferId)
        require(id.toString().equals(transferId, true))
        require(offset in 0..MAX_FILE_BYTES && data.size in 1..MAX_DATA_BYTES)
        require(offset <= MAX_FILE_BYTES - data.size)
        return ByteBuffer.allocate(28 + data.size)
            .apply {
                put(MAGIC)
                putLong(id.mostSignificantBits)
                putLong(id.leastSignificantBits)
                putLong(offset)
                put(data)
            }
            .array()
    }

    companion object {
        const val MAX_DATA_BYTES = 16_384
        const val MAX_FILE_BYTES = 2_147_483_648L
        private val MAGIC = "AFC1".toByteArray(Charsets.US_ASCII)

        fun decode(frame: ByteArray): FileChunk {
            require(frame.size in 29..(28 + MAX_DATA_BYTES) && frame.take(4) == MAGIC.toList())
            val buffer = ByteBuffer.wrap(frame)
            buffer.position(4)
            val id = UUID(buffer.long, buffer.long)
            val offset = buffer.long
            require(offset in 0..MAX_FILE_BYTES)
            require(offset <= MAX_FILE_BYTES - buffer.remaining())
            return FileChunk(
                id.toString(),
                offset,
                ByteArray(buffer.remaining()).also { buffer.get(it) },
            )
        }
    }
}
