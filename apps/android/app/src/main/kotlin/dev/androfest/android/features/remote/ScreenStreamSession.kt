package dev.androfest.android.features.remote

import android.content.Context
import dev.twinvia.protocol.*
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString

/** Shared encrypted, bounded protocol for optional Classic and local-network screen sockets. */
internal suspend fun serveScreenStream(
    context: Context,
    channel: RemoteChannel,
    source: InputStream,
    sink: OutputStream,
    close: () -> Unit,
) = coroutineScope {
    val authenticated = AtomicBoolean(false)
    val watchdog = launch {
        delay(5_000)
        if (!authenticated.get()) runCatching { close() }
    }
    try {
        val cipher = RemoteFrameCipher(channel, mac = false)
        val input = DataInputStream(source)
        val output = DataOutputStream(sink)
        while (isActive) {
            val length = input.readInt()
            require(length in 24..1024) { "Invalid screen request." }
            val sealed = ByteArray(length)
            input.readFully(sealed)
            val mode = cipher.open(sealed).decodeToString()
            require(mode in listOf("detail", "responsive"))
            authenticated.set(true)
            watchdog.cancel()
            val reply =
                try {
                    RemoteControlSession.requireActive(context)
                    val service =
                        RemoteAccessibilityService.current
                            ?: error("Screen service is unavailable.")
                    val screen = service.snapshot(mode == "detail")
                    RemoteControlSession.requireActive(context)
                    FastScreenReply(screen = screen)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (error: Exception) {
                    FastScreenReply(error = (error.message ?: "Screen capture failed.").take(128))
                }
            val response = cipher.seal(WireCodec.json.encodeToString(reply).toByteArray())
            output.writeInt(response.size)
            output.write(response)
            output.flush()
            if (reply.error != null) break
        }
    } finally {
        watchdog.cancel()
    }
}
