package dev.androfest.android.features.calls

import android.content.Context
import android.os.Process
import java.io.*
import java.net.*
import java.security.*
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import org.json.JSONObject

/**
 * Authenticated local adapter. Remote PCM is carried only by the existing pinned TLS connection.
 */
class CallAudioRelay(private val context: Context, private val scope: CoroutineScope) {
    @Volatile private var output: DataOutputStream? = null
    @Volatile private var socket: Socket? = null
    @Volatile private var activeId: String? = null
    private val lock = Any()
    private val pending =
        java.util.concurrent.ConcurrentHashMap<String, CompletableDeferred<Unit>>()
    private val uplinkDiscards = java.util.concurrent.atomic.AtomicInteger()
    private val uplink =
        Channel<ByteArray>(
            32,
            kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST,
            onUndeliveredElement = { uplinkDiscards.incrementAndGet() },
        )
    var onAudio: ((ByteArray) -> Unit)? = null
    var onStopped: ((String) -> Unit)? = null
    @Volatile private var received = 0
    @Volatile private var sent = 0
    @Volatile private var failure = ""

    init {
        scope.launch {
            val preferences = context.getSharedPreferences("call-audio", Context.MODE_PRIVATE)
            val server =
                ServerSocket().apply {
                    reuseAddress = true
                    val address = InetAddress.getByName("127.0.0.1")
                    runCatching { bind(InetSocketAddress(address, preferences.getInt("port", 0))) }
                        .getOrElse { bind(InetSocketAddress(address, 0)) }
                }
            check(preferences.edit().putInt("port", server.localPort).commit())
            val secret =
                preferences.getString("secret", null)
                    ?: randomHex(32).also {
                        check(preferences.edit().putString("secret", it).commit())
                    }
            java.io
                .File(context.filesDir, "call-audio-helper.json")
                .writeText(
                    JSONObject()
                        .put("uid", Process.myUid())
                        .put("port", server.localPort)
                        .put("secret", secret)
                        .toString()
                )
            server.use {
                while (isActive) {
                    val peer = server.accept()
                    try {
                        peer.tcpNoDelay = true
                        peer.soTimeout = 3000
                        val input = DataInputStream(peer.inputStream)
                        val stream = DataOutputStream(peer.outputStream)
                        val nonce = randomHex(16)
                        write(
                            stream,
                            JSONObject()
                                .put("kind", "challenge")
                                .put("nonce", nonce)
                                .toString()
                                .toByteArray(),
                        )
                        val auth = JSONObject(String(read(input)))
                        val remote = auth.getString("nonce")
                        require(
                            auth.getString("kind") == "authenticate" &&
                                remote.matches(Regex("[a-f0-9]{32}"))
                        )
                        require(
                            MessageDigest.isEqual(
                                auth.getString("proof").toByteArray(),
                                proof(secret, "androfest.call-audio.helper.v1\n$nonce\n$remote")
                                    .toByteArray(),
                            )
                        )
                        write(
                            stream,
                            JSONObject()
                                .put("kind", "authenticated")
                                .put(
                                    "proof",
                                    proof(secret, "androfest.call-audio.app.v1\n$nonce\n$remote"),
                                )
                                .toString()
                                .toByteArray(),
                        )
                        peer.soTimeout = 0
                        synchronized(lock) {
                            socket = peer
                            output = stream
                        }
                        while (isActive) {
                            val frame = read(input)
                            if (frame[0] == 65.toByte()) {
                                if (packetId(frame) == activeId) {
                                    received++
                                    onAudio?.invoke(frame)
                                }
                            } else {
                                val message = JSONObject(String(frame))
                                when (message.getString("kind")) {
                                    "ready" -> require(message.getInt("version") == 1)
                                    "started" ->
                                        pending.remove(message.getString("id"))?.complete(Unit)
                                    "failed" -> {
                                        failure =
                                            message.getString("reason") +
                                                ":mode=" +
                                                message.getInt("mode")
                                        pending
                                            .remove(message.getString("id"))
                                            ?.completeExceptionally(
                                                IllegalStateException(
                                                    "Could not open the call audio channel ($failure)"
                                                )
                                            )
                                    }
                                    "stopped" ->
                                        if (activeId == message.getString("id")) {
                                            val id = activeId!!
                                            activeId = null
                                            onStopped?.invoke(id)
                                        }
                                    else -> error("Invalid audio state")
                                }
                            }
                        }
                    } catch (error: Exception) {
                        if (error is CancellationException) throw error
                    } finally {
                        val old = activeId
                        activeId = null
                        synchronized(lock) {
                            socket = null
                            output = null
                        }
                        peer.close()
                        pending.values.forEach {
                            it.completeExceptionally(IllegalStateException("Audio helper stopped"))
                        }
                        pending.clear()
                        if (old != null) onStopped?.invoke(old)
                    }
                }
            }
        }
        scope.launch {
            for (frame in uplink) if (packetId(frame) == activeId) {
                try {
                    synchronized(lock) { write(output ?: error("Audio helper stopped"), frame) }
                    sent++
                } catch (_: Exception) {
                    runCatching { socket?.close() }
                }
            }
        }
        scope.launch {
            while (isActive) {
                if (dev.androfest.android.BuildConfig.DEBUG)
                    runCatching {
                        java.io
                            .File(context.filesDir, "call-audio-status.json")
                            .writeText(
                                JSONObject()
                                    .put("helperReady", output != null)
                                    .put("active", activeId != null)
                                    .put("downlinkPackets", received)
                                    .put("uplinkPackets", sent)
                                    .put("uplinkQueueDiscards", uplinkDiscards.get())
                                    .put("lastFailure", failure)
                                    .toString()
                            )
                    }
                delay(1000)
            }
        }
    }

    suspend fun start(id: String) {
        require(UUID.fromString(id).toString() == id)
        stop()
        val acknowledgement = CompletableDeferred<Unit>()
        pending[id] = acknowledgement
        activeId = id
        try {
            send(JSONObject().put("kind", "start").put("id", id))
            withTimeout(5000) { acknowledgement.await() }
        } catch (error: Exception) {
            stop()
            throw error
        } finally {
            pending.remove(id)
        }
    }

    fun stop(id: String? = null) {
        if (id != null && id != activeId) return
        val old = activeId
        activeId = null
        if (old != null) runCatching { send(JSONObject().put("kind", "stop")) }
    }

    fun receive(frame: ByteArray) {
        if (packetId(frame) == activeId) uplink.trySend(frame)
    }

    private fun send(value: JSONObject) =
        synchronized(lock) {
            write(
                output ?: error("Activate call audio helper over USB"),
                value.toString().toByteArray(),
            )
        }

    private fun packetId(frame: ByteArray): String {
        require(frame.size in 22..1940 && (frame.size - 20) % 2 == 0)
        val buffer = java.nio.ByteBuffer.wrap(frame)
        require(buffer.int == 0x41415031)
        return UUID(buffer.long, buffer.long).toString()
    }

    private fun read(input: DataInputStream): ByteArray {
        val size = input.readInt()
        require(size in 1..4096)
        return ByteArray(size).also(input::readFully)
    }

    private fun write(stream: DataOutputStream, bytes: ByteArray) {
        require(bytes.size in 1..4096)
        stream.write(
            java.nio.ByteBuffer.allocate(4 + bytes.size).putInt(bytes.size).put(bytes).array()
        )
        stream.flush()
    }

    private fun randomHex(count: Int) =
        ByteArray(count)
            .also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it) }

    private fun proof(secret: String, text: String) =
        Mac.getInstance("HmacSHA256")
            .apply {
                init(
                    SecretKeySpec(
                        secret.chunked(2).map { it.toInt(16).toByte() }.toByteArray(),
                        "HmacSHA256",
                    )
                )
            }
            .doFinal(text.toByteArray())
            .joinToString("") { "%02x".format(it) }
}
