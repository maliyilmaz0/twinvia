package dev.androfest.android.features.remote

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import dev.twinvia.protocol.RemoteChannel
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.*

/** Explicit, phone-approved Wi-Fi listener bound to one RFC1918 address, not every interface. */
object LanScreenServer {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var listener: ServerSocket? = null
    private var socket: Socket? = null
    private var generation = 0L
    private var worker: Job? = null

    fun open(context: Context): RemoteChannel {
        RemoteControlSession.requireActive(context)
        return openOnWifi(context)
    }

    @Synchronized
    private fun openOnWifi(context: Context): RemoteChannel {
        stop()
        val connectivity = context.getSystemService(ConnectivityManager::class.java)
        val address =
            connectivity.allNetworks
                .asSequence()
                .filter {
                    val caps = connectivity.getNetworkCapabilities(it)
                    caps?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true &&
                        !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                }
                .flatMap {
                    connectivity.getLinkProperties(it)?.linkAddresses.orEmpty().asSequence()
                }
                .map { it.address }
                .filterIsInstance<Inet4Address>()
                .firstOrNull { RemoteChannel.isPrivateIPv4(it.hostAddress.orEmpty()) }
                ?: error("Connect the phone to a private Wi-Fi network first.")
        val server = ServerSocket()
        try {
            server.bind(InetSocketAddress(address, 0), 1)
            server.soTimeout = 15_000
        } catch (error: Exception) {
            runCatching { server.close() }
            throw error
        }
        listener = server
        val channel =
            RemoteChannel(
                UUID.randomUUID().toString(),
                Base64.getEncoder()
                    .encodeToString(ByteArray(32).also { SecureRandom().nextBytes(it) }),
                address.hostAddress,
                server.localPort,
            )
        channel.validate()
        val current = generation
        worker = scope.launch {
            var accepted: Socket? = null
            try {
                accepted = server.accept()
                if (!admit(current, accepted)) return@launch
                server.close()
                accepted.tcpNoDelay = true
                accepted.soTimeout = 30_000
                val client = accepted
                serveScreenStream(context, channel, client.inputStream, client.outputStream) {
                    client.close()
                }
            } catch (_: Exception) {
                // No content, network address, key, or application data is logged.
            } finally {
                runCatching { accepted?.close() }
                finish(current)
            }
        }
        return channel
    }

    @Synchronized
    private fun admit(expected: Long, next: Socket): Boolean {
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
