package dev.twinvia.protocol

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer

/** Length-prefixed TLS framing; validate before allocating or writing the payload. */
object WireFrame {
    fun read(input: InputStream): ByteArray {
        val stream = DataInputStream(input)
        val length = stream.readInt()
        require(length in 1..WireCodec.MAX_MESSAGE_BYTES)
        return ByteArray(length).also(stream::readFully)
    }

    fun encode(payload: ByteArray): ByteArray {
        require(payload.size in 1..WireCodec.MAX_MESSAGE_BYTES)
        return ByteBuffer.allocate(4 + payload.size).putInt(payload.size).put(payload).array()
    }

    /** The session owner serializes writes to avoid interleaved frames. */
    fun write(output: OutputStream, payload: ByteArray) {
        DataOutputStream(output).apply {
            write(encode(payload))
            flush()
        }
    }
}
