package dev.androfest.android.features.remote

import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.Context
import dev.twinvia.protocol.*
import java.io.DataInputStream
import java.io.DataOutputStream
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.*
import kotlinx.serialization.encodeToString

/** Optional RFCOMM screenshot lane. It never starts or extends the phone-side lease. */
object FastScreenServer {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var listener: BluetoothServerSocket? = null
    private var socket: BluetoothSocket? = null
    private var generation = 0L
    private var worker: Job? = null

    @Synchronized
    fun open(context: Context): RemoteChannel {
        stop()
        check(
            context.checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            "Allow Nearby Devices permission first."
        }
        val adapter =
            context.getSystemService(BluetoothManager::class.java).adapter
                ?: error("Bluetooth Classic is unavailable.")
        check(adapter.isEnabled) { "Enable Bluetooth first." }
        val server =
            adapter.listenUsingRfcommWithServiceRecord(
                "Twinvia Mirror",
                UUID.fromString(RemoteChannel.SERVICE_ID),
            )
        listener = server
        val channel =
            RemoteChannel(
                UUID.randomUUID().toString(),
                Base64.getEncoder()
                    .encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }),
            )
        val current = generation
        worker = scope.launch {
            var accepted: BluetoothSocket? = null
            try {
                accepted = server.accept(15_000)
                if (!admit(current, accepted)) return@launch
                server.close()
                val authenticated = AtomicBoolean(false)
                val watchdog = launch {
                    delay(5_000)
                    if (!authenticated.get()) runCatching { accepted.close() }
                }
                try {
                    val cipher = RemoteFrameCipher(channel, mac = false)
                    val input = DataInputStream(accepted.inputStream)
                    val output = DataOutputStream(accepted.outputStream)
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
                                FastScreenReply(
                                    error = (error.message ?: "Screen capture failed.").take(128)
                                )
                            }
                        val response =
                            cipher.seal(WireCodec.json.encodeToString(reply).toByteArray())
                        output.writeInt(response.size)
                        output.write(response)
                        output.flush()
                        if (reply.error != null) break
                    }
                } finally {
                    watchdog.cancel()
                }
            } catch (_: Exception) {
                // No payload, credentials, or screen content enters logs.
            } finally {
                runCatching { accepted?.close() }
                finish(current)
            }
        }
        return channel
    }

    @Synchronized
    private fun admit(expected: Long, next: BluetoothSocket): Boolean {
        if (generation != expected) {
            next.close()
            return false
        }
        socket = next
        return true
    }

    @Synchronized
    private fun finish(expected: Long) {
        if (generation == expected) stop()
    }

    @Synchronized
    fun stop() {
        generation++
        runCatching { listener?.close() }
        listener = null
        runCatching { socket?.close() }
        socket = null
        worker?.cancel()
        worker = null
    }
}
