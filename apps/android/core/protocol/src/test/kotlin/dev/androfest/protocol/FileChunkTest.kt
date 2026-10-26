package dev.androfest.protocol

import java.util.Base64
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class FileChunkTest {
    private val id = "12345678-1234-4234-9234-123456789abc"

    @Test
    fun `independent binary fixture`() {
        val text = javaClass.classLoader!!.getResource("binary/file-chunk.json")!!.readText()
        val fixture = WireCodec.json.parseToJsonElement(text).jsonObject
        val frame =
            Base64.getDecoder().decode(fixture.getValue("frameBase64").jsonPrimitive.content)
        val chunk = FileChunk.decode(frame)
        assertEquals(fixture.getValue("transferId").jsonPrimitive.content, chunk.transferId)
        assertEquals(fixture.getValue("offset").jsonPrimitive.long, chunk.offset)
        assertEquals(
            fixture.getValue("text").jsonPrimitive.content,
            chunk.data.toString(Charsets.UTF_8),
        )
        assertArrayEquals(frame, chunk.encode())
    }

    @Test
    fun `maximum chunk and file boundary`() {
        val data = ByteArray(FileChunk.MAX_DATA_BYTES) { 42 }
        assertArrayEquals(
            data,
            FileChunk.decode(FileChunk(id, FileChunk.MAX_FILE_BYTES - data.size, data).encode())
                .data,
        )
        assertThrows(IllegalArgumentException::class.java) {
            FileChunk(id, FileChunk.MAX_FILE_BYTES, byteArrayOf(1)).encode()
        }
    }

    @Test
    fun `invalid payloads rejected`() {
        listOf(ByteArray(0), ByteArray(FileChunk.MAX_DATA_BYTES + 1)).forEach {
            assertThrows(IllegalArgumentException::class.java) { FileChunk(id, 0, it).encode() }
        }
        assertThrows(IllegalArgumentException::class.java) {
            FileChunk(id, -1, byteArrayOf(1)).encode()
        }
        assertThrows(IllegalArgumentException::class.java) {
            FileChunk("bad-id", 0, byteArrayOf(1)).encode()
        }
    }

    @Test
    fun `truncated and unknown frames rejected`() {
        val frame = FileChunk(id, 7, byteArrayOf(1)).encode()
        assertThrows(IllegalArgumentException::class.java) { FileChunk.decode(frame.copyOf(28)) }
        frame[0] = 0
        assertThrows(IllegalArgumentException::class.java) { FileChunk.decode(frame) }
    }
}
