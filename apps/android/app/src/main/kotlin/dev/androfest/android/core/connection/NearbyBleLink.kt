package dev.androfest.android.core.connection

import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import dev.androfest.protocol.*
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLSocket
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** BLE is only a bounded byte pipe; pinned TLS + the saved QR secret authenticate app data. */
class NearbyBleLink(
    private val context: Context,
    private val invitation: () -> PairingInvitation?,
    private val introduction: (PairingInvitation) -> PairingIntroduction?,
    private val connectionReady: () -> Boolean,
) : PeerLink {
    private val handler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = Nearby.getConnectionsClient(context)
    private val mutableStatus = MutableStateFlow("Preparing Bluetooth connection")
    override val status = mutableStatus.asStateFlow()
    private val allowedPorts = ConcurrentHashMap.newKeySet<Int>()
    private var currentInvitation: String? = null
    private var discovering = false
    private var starting = false
    private var endpoint: String? = null
    private var nextRetry = 0L
    private var retryDelay = 2_000L
    private var generation = 0
    @Volatile private var tunnel: Tunnel? = null

    private class Tunnel(val endpoint: String, val generation: Int, val socket: Socket) {
        val inbound = Channel<NearbyBleProtocol.Packet>(capacity = 1)
        val ackLock = Any()
        var acknowledgement: Pair<Int, CompletableDeferred<Unit>>? = null
        var job: Job? = null
    }

    override fun start() {
        handler.post(
            object : Runnable {
                override fun run() {
                    runCatching { tick() }
                        .onFailure {
                            reset()
                            mutableStatus.value = "Retrying Bluetooth"
                        }
                    handler.postDelayed(this, if (connectionReady()) 15_000 else 5_000)
                }
            }
        )
    }

    override fun restart() {
        handler.post {
            reset()
            nextRetry = 0
            tick()
        }
    }

    override fun permits(socket: SSLSocket): Boolean =
        socket.localAddress.isLoopbackAddress &&
            socket.inetAddress.isLoopbackAddress &&
            socket.port in allowedPorts

    private fun permitted() =
        listOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE,
                Manifest.permission.NEARBY_WIFI_DEVICES,
            )
            .all {
                context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
            }

    private fun tick() {
        if (!permitted()) {
            reset()
            mutableStatus.value = "Allow Nearby Devices permission to connect"
            return
        }
        val bluetooth = context.getSystemService(BluetoothManager::class.java)?.adapter
        if (bluetooth?.isEnabled != true) {
            reset()
            mutableStatus.value = "Turn on Bluetooth on your phone"
            return
        }
        val saved = invitation()
        if (saved == null) {
            reset()
            currentInvitation = null
            mutableStatus.value = "Pair with your Mac first"
            return
        }
        if (currentInvitation != saved.id) {
            reset()
            currentInvitation = saved.id
            nextRetry = 0
        }
        if (connectionReady()) {
            retryDelay = 2_000
            mutableStatus.value = "Bluetooth LE · Encrypted connection active"
            return
        }
        if (
            endpoint == null &&
                !discovering &&
                !starting &&
                android.os.SystemClock.elapsedRealtime() >= nextRetry
        )
            discover(saved)
    }

    private fun discover(saved: PairingInvitation) {
        val run = generation
        starting = true
        mutableStatus.value = "Looking for your Mac over Bluetooth"
        client
            .startDiscovery(
                NearbyBleProtocol.serviceId(saved),
                object : EndpointDiscoveryCallback() {
                    override fun onEndpointFound(id: String, info: DiscoveredEndpointInfo) {
                        if (
                            run != generation ||
                                endpoint != null ||
                                !MessageDigest.isEqual(
                                    info.endpointInfo,
                                    NearbyBleProtocol.context("mac", saved),
                                )
                        )
                            return
                        endpoint = id
                        mutableStatus.value = "Establishing an encrypted Bluetooth channel with Mac"
                        client
                            .requestConnection(
                                NearbyBleProtocol.context("phone", saved),
                                id,
                                lifecycle(run, saved),
                                ConnectionOptions.Builder()
                                    .setConnectionType(ConnectionType.NON_DISRUPTIVE)
                                    .build(),
                            )
                            .addOnFailureListener { if (generation == run) reset() }
                        handler.postDelayed(
                            { if (generation == run && !connectionReady()) reset() },
                            35_000,
                        )
                    }

                    override fun onEndpointLost(id: String) {}
                },
                DiscoveryOptions.Builder()
                    .setStrategy(Strategy.P2P_POINT_TO_POINT)
                    .setLowPower(true)
                    .build(),
            )
            .addOnSuccessListener {
                if (generation == run) {
                    starting = false
                    discovering = true
                }
            }
            .addOnFailureListener { if (generation == run) reset() }
    }

    private fun lifecycle(run: Int, saved: PairingInvitation) =
        object : ConnectionLifecycleCallback() {
            override fun onConnectionInitiated(id: String, info: ConnectionInfo) {
                if (
                    run != generation ||
                        endpoint != id ||
                        !MessageDigest.isEqual(
                            info.endpointInfo,
                            NearbyBleProtocol.context("mac", saved),
                        )
                ) {
                    client.rejectConnection(id)
                    return
                }
                // No user data is accepted on Nearby alone. TLS certificate pinning
                // and the QR secret still authenticate the actual application session.
                client.acceptConnection(id, payload(run)).addOnFailureListener {
                    if (generation == run) reset()
                }
            }

            override fun onConnectionResult(id: String, result: ConnectionResolution) {
                if (run != generation || endpoint != id) return
                if (!result.status.isSuccess) {
                    reset()
                    return
                }
                client.stopDiscovery()
                discovering = false
                starting = false
                val intro =
                    introduction(saved)
                        ?: run {
                            reset()
                            return
                        }
                val socket = Socket()
                val value = Tunnel(id, run, socket)
                tunnel = value
                value.job = scope.launch {
                    try {
                        socket.bind(InetSocketAddress(InetAddress.getLoopbackAddress(), 0))
                        allowedPorts.add(socket.localPort)
                        socket.tcpNoDelay = true
                        socket.connect(
                            InetSocketAddress(InetAddress.getLoopbackAddress(), intro.port),
                            8_000,
                        )
                        send(
                            id,
                            NearbyBleProtocol.encode(
                                NearbyBleProtocol.Packet(
                                    1,
                                    data = PairingIntroductionCodec.encodeIntroduction(intro),
                                )
                            ),
                        )
                        coroutineScope {
                            launch {
                                try {
                                    var expected = 0
                                    for (packet in value.inbound) {
                                        check(packet.sequence == expected++)
                                        socket.outputStream.write(packet.data)
                                        socket.outputStream.flush()
                                        send(
                                            id,
                                            NearbyBleProtocol.encode(
                                                NearbyBleProtocol.Packet(3, packet.sequence)
                                            ),
                                        )
                                    }
                                } finally {
                                    runCatching { socket.close() }
                                }
                            }
                            var sequence = 0
                            val buffer = ByteArray(NearbyBleProtocol.MAX_CHUNK)
                            while (isActive && tunnel === value) {
                                val count = socket.inputStream.read(buffer)
                                check(count > 0)
                                val next = sequence++
                                val ack = CompletableDeferred<Unit>()
                                synchronized(value.ackLock) { value.acknowledgement = next to ack }
                                send(
                                    id,
                                    NearbyBleProtocol.encode(
                                        NearbyBleProtocol.Packet(2, next, buffer.copyOf(count))
                                    ),
                                )
                                withTimeout(25_000) { ack.await() }
                            }
                        }
                    } catch (error: Exception) {
                        if (error !is CancellationException)
                            handler.post { if (generation == run) reset() }
                    } finally {
                        allowedPorts.remove(socket.localPort)
                        runCatching { socket.close() }
                    }
                }
            }

            override fun onDisconnected(id: String) {
                if (generation == run && endpoint == id) reset()
            }
        }

    private fun payload(run: Int) =
        object : PayloadCallback() {
            override fun onPayloadReceived(id: String, payload: Payload) {
                if (run != generation || endpoint != id) return
                try {
                    val value = tunnel ?: error("Tunnel not ready")
                    require(payload.type == Payload.Type.BYTES)
                    val packet =
                        NearbyBleProtocol.decode(payload.asBytes() ?: error("Empty BLE packet"))
                    when (packet.kind) {
                        2 -> check(value.inbound.trySend(packet).isSuccess)
                        3 ->
                            synchronized(value.ackLock) {
                                val pending = value.acknowledgement
                                check(pending?.first == packet.sequence)
                                value.acknowledgement = null
                                pending.second.complete(Unit)
                            }
                        else -> error("Unexpected BLE packet")
                    }
                } catch (_: Exception) {
                    reset()
                }
            }

            override fun onPayloadTransferUpdate(id: String, update: PayloadTransferUpdate) {
                if (
                    run == generation &&
                        endpoint == id &&
                        update.status == PayloadTransferUpdate.Status.FAILURE
                )
                    reset()
            }
        }

    private suspend fun send(id: String, bytes: ByteArray) =
        suspendCancellableCoroutine<Unit> { continuation ->
            client
                .sendPayload(id, Payload.fromBytes(bytes))
                .addOnSuccessListener { if (continuation.isActive) continuation.resume(Unit) }
                .addOnFailureListener {
                    if (continuation.isActive) continuation.resumeWithException(it)
                }
        }

    private fun reset() {
        generation++
        val previous = endpoint
        endpoint = null
        client.stopDiscovery()
        discovering = false
        starting = false
        val old = tunnel
        tunnel = null
        old?.inbound?.close()
        old?.let {
            synchronized(it.ackLock) {
                it.acknowledgement?.second?.cancel()
                it.acknowledgement = null
            }
            allowedPorts.remove(it.socket.localPort)
            runCatching { it.socket.close() }
            it.job?.cancel()
        }
        if (previous != null) client.disconnectFromEndpoint(previous)
        nextRetry = android.os.SystemClock.elapsedRealtime() + retryDelay
        retryDelay = minOf(retryDelay * 2, 30_000)
        mutableStatus.value = "Retrying Bluetooth connection"
    }
}
