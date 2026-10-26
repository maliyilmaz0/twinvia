package dev.androfest.android.core.connection

import android.content.Context
import dev.androfest.android.core.device.DeviceIdentity
import dev.androfest.android.features.device.DeviceFeatures
import dev.androfest.android.features.device.PhoneDataProvider
import dev.androfest.android.features.files.FileTransferManager
import dev.androfest.android.features.notifications.NotificationRepository
import dev.twinvia.protocol.*
import java.io.DataInputStream
import java.util.concurrent.Semaphore
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class BridgeRepository(
    context: Context,
    private val identity: DeviceIdentity,
    private val notifications: NotificationRepository,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val store = SecurePeerStore(context)
    private val saved = AtomicReference<PairingInvitation?>(null)
    private val pending = AtomicReference<PairingInvitation?>(null)
    private val active = AtomicReference<SSLSocket?>(null)
    private val writeLock = Any()
    private val peerLock = Any()
    private val slots = Semaphore(4)

    private sealed interface FilePacket {
        val socket: SSLSocket

        data class Control(override val socket: SSLSocket, val envelope: WireEnvelope) : FilePacket

        data class Chunk(override val socket: SSLSocket, val value: FileChunk) : FilePacket
    }

    private val filePackets = Channel<FilePacket>(capacity = 4)

    private data class CommandPacket(val socket: SSLSocket, val envelope: WireEnvelope)

    private val commands = Channel<CommandPacket>(capacity = 8)
    val features = DeviceFeatures(context.applicationContext, notifications, scope)
    private val peerLink: PeerLink =
        NearbyBleLink(
            context.applicationContext,
            { pending.get()?.takeIf { it.expiresAt > System.currentTimeMillis() } ?: saved.get() },
            { invitation ->
                val port = server?.localPort
                val fingerprint = tls?.fingerprint
                if (port != null && fingerprint != null)
                    PairingIntroduction.create(
                        invitation,
                        identity.id,
                        PairingIntroductionCodec.compactName(identity.name),
                        port,
                        fingerprint,
                    )
                else null
            },
            {
                active.get()?.let { !it.isClosed } == true
            },
        )
    val transportStatus = peerLink.status
    private var server: SSLServerSocket? = null
    private var tls: TlsIdentity? = null
    private val _status = MutableStateFlow("Not paired with a Mac")
    val status = _status.asStateFlow()
    private val _connected = MutableStateFlow(false)
    val connected = _connected.asStateFlow()
    private val _peerName = MutableStateFlow<String?>(null)
    val peerName = _peerName.asStateFlow()
    private val _peerCapabilities = MutableStateFlow<List<String>>(emptyList())
    val peerCapabilities = _peerCapabilities.asStateFlow()
    val files =
        FileTransferManager(
            context,
            scope,
            identity.id,
            { _connected.value },
            { event ->
                val socket = active.get() ?: error("Device disconnected")
                writeFrame(socket, WireCodec.encode(event))
            },
            { bytes ->
                val socket = active.get() ?: error("Device disconnected")
                writePayload(socket, bytes)
            },
        )

    val handoff =
        dev.androfest.android.features.calls.PhoneCallHandoff(context.applicationContext, scope)
    private val statusWakeup = Channel<Unit>(Channel.CONFLATED)
    private val callAudio =
        dev.androfest.android.features.calls.CallAudioRelay(context.applicationContext, scope)
    private val phoneData = PhoneDataProvider(context.applicationContext, files)
    private val commandProcessor =
        CommandProcessor(DeviceCommandHandler(handoff, callAudio, phoneData, features))

    init {
        scope.launch {
            runCatching {
                    handoff.onChanged = {
                        statusWakeup.trySend(Unit)
                        if (handoff.state.value.state == "idle") scope.launch { callAudio.stop() }
                    }
                    callAudio.onAudio = { bytes ->
                        active.get()?.let { socket ->
                            runCatching { writePayload(socket, bytes) }
                                .onFailure { runCatching { socket.close() } }
                        }
                    }
                    callAudio.onStopped = { id ->
                        sendEvent(
                            WireCodec.message(
                                MessageType.COMMAND_RESULT,
                                identity.id,
                                CommandResult(id, false, "Call audio relay stopped"),
                            )
                        )
                    }
                    features.clipboard.onChanged = { text ->
                        if (_connected.value && "clipboard.sync" in _peerCapabilities.value) {
                            scope.launch {
                                sendEvent(
                                    WireCodec.message(
                                        MessageType.TEXT_SHARED,
                                        identity.id,
                                        SharedText(text, isClipboard = true),
                                    )
                                )
                            }
                        }
                    }
                    saved.set(store.load())
                    _peerName.value = saved.get()?.name
                    tls = TlsIdentity()
                    server =
                        (tls!!
                                .context()
                                .serverSocketFactory
                                .createServerSocket(0, 4, java.net.InetAddress.getLoopbackAddress())
                                as SSLServerSocket)
                            .apply {
                                enabledProtocols = arrayOf("TLSv1.3", "TLSv1.2")
                                needClientAuth = false
                            }
                    if (dev.androfest.android.BuildConfig.DEBUG)
                        android.util.Log.d(
                            "TwinviaConnection",
                            "TLS server port ${server!!.localPort}",
                        )
                    if (saved.get() != null) _status.value = "Waiting for Mac connection"
                    launch { expirePendingPairing() }
                    peerLink.start()
                    launch {
                        for (packet in commands) {
                            if (active.get() !== packet.socket) continue
                            val request = packet.envelope
                            val result =
                                commandProcessor.process(request) { active.get() === packet.socket }
                            if (active.get() === packet.socket)
                                sendEvent(
                                    WireCodec.message(
                                        MessageType.COMMAND_RESULT,
                                        identity.id,
                                        result,
                                    )
                                )
                        }
                    }
                    launch {
                        for (packet in filePackets) {
                            if (active.get() !== packet.socket) continue
                            try {
                                when (packet) {
                                    is FilePacket.Control -> files.receive(packet.envelope)
                                    is FilePacket.Chunk -> files.receiveChunk(packet.value)
                                }
                            } catch (error: Exception) {
                                if (error is CancellationException) throw error
                                runCatching { packet.socket.close() }
                            }
                        }
                    }
                    launch {
                        notifications.outbound.collect { event ->
                            if (
                                notifications.isCapturing ||
                                    event.type == MessageType.NOTIFICATION_REMOVED
                            )
                                sendEvent(event)
                        }
                    }
                    while (isActive) {
                        val socket = server!!.accept() as SSLSocket
                        if (!slots.tryAcquire()) {
                            socket.close()
                            continue
                        }
                        launch {
                            try {
                                serve(socket)
                            } finally {
                                slots.release()
                            }
                        }
                    }
                }
                .onFailure {
                    _status.value = "Could not start the connection service. Reopen the app."
                }
        }
    }

    fun pair(link: String) {
        val invitation = PairingInvitation.fromLink(link)
        synchronized(peerLock) {
            // A new QR scan explicitly replaces the previous association on this phone.
            active.getAndSet(null)?.close()
            _connected.value = false
            features.clipboard.setConnected(false)
            handoff.setConnected(false)
            saved.set(null)
            store.clear()
            pending.set(invitation)
            _peerName.value = invitation.name
            _status.value = "${invitation.name} establishing a direct connection"
        }
        peerLink.restart()
    }

    fun forget() {
        scope.launch {
            synchronized(peerLock) {
                saved.set(null)
                pending.set(null)
                active.getAndSet(null)?.close()
                store.clear()
                _peerName.value = null
                _connected.value = false
                callAudio.stop()
                features.clipboard.setConnected(false)
                handoff.setConnected(false)
                _status.value = "Not paired with a Mac"
            }
        }
    }

    fun sendTest() {
        scope.launch {
            val message =
                WireCodec.message(
                    MessageType.NOTIFICATION_POSTED,
                    identity.id,
                    NotificationPosted(
                        key = "androfest-connection-test",
                        packageName = "dev.androfest.android",
                        appName = "Twinvia",
                        title = "Phone and Mac connected",
                        text = "This test message arrived through the encrypted device connection.",
                        postedAt = System.currentTimeMillis(),
                        canReply = false,
                    ),
                )
            sendEvent(message)
        }
    }

    fun retryConnection() {
        peerLink.restart()
    }

    fun sendText(text: String) {
        require(_connected.value) { "Connect to Mac first." }
        require("text.share" in _peerCapabilities.value) { "Update the Mac application." }
        val event = WireCodec.message(MessageType.TEXT_SHARED, identity.id, SharedText(text))
        scope.launch { sendEvent(event) }
    }

    private suspend fun expirePendingPairing() {
        while (currentCoroutineContext().isActive) {
            synchronized(peerLock) {
                val invitation = pending.get()
                if (
                    invitation != null &&
                        invitation.expiresAt <= System.currentTimeMillis() &&
                        pending.compareAndSet(invitation, null)
                ) {
                    _peerName.value = null
                    _status.value = "QR code expired. Refresh it on Mac."
                }
            }
            delay(3000)
        }
    }

    private fun isAdmittedSocket(socket: SSLSocket): Boolean = peerLink.permits(socket)

    private suspend fun serve(socket: SSLSocket) {
        try {
            // Loopback only; accept the exact local socket created by our BLE
            // tunnel. Other local apps still cannot reach the application session.
            require(isAdmittedSocket(socket)) { "Only the app-owned direct tunnel is admitted." }
            socket.tcpNoDelay = true
            socket.soTimeout = 25_000
            socket.startHandshake()
            val input = DataInputStream(socket.inputStream)
            val authentication =
                WireCodec.json.decodeFromString<SessionAuthentication>(readFrame(input))
            val authenticated = synchronized(peerLock) { authenticate(authentication) }
            // Only a validated new session can end an existing transfer.
            files.disconnected()
            callAudio.stop()
            synchronized(peerLock) {
                val invitation = authenticate(authentication)
                require(invitation === authenticated)
                if (pending.get() === invitation) {
                    store.save(invitation)
                    saved.set(invitation)
                    pending.set(null)
                }
                writeFrame(
                    socket,
                    WireCodec.encode(
                        WireCodec.message(
                            MessageType.DEVICE_HELLO,
                            identity.id,
                            identity
                                .hello()
                                .copy(
                                    capabilities =
                                        listOf(
                                            "notifications.send",
                                            "connection.test",
                                            "files.send",
                                            "files.receive",
                                            "device.commands",
                                            "notifications.actions",
                                            "text.share",
                                            "device.status",
                                            "clipboard.sync",
                                            "clipboard.image.receive",
                                            "call.handoff",
                                            "phone.browse",
                                        )
                                ),
                        )
                    ),
                )
                active.getAndSet(socket)?.close()
                _peerName.value = invitation.name
                _peerCapabilities.value = authentication.capabilities
            }
            _connected.value = true
            features.clipboard.setConnected(true)
            handoff.setConnected(true)
            _status.value = "${_peerName.value} connected · Encrypted direct connection"
            val statusJob = scope.launch {
                var previous: DeviceStatus? = null
                while (
                    "device.status" in authentication.capabilities &&
                        active.get() === socket &&
                        isActive
                ) {
                    val current =
                        withContext(Dispatchers.Main) {
                            features.status().copy(call = handoff.status())
                        }
                    if (current != previous && active.get() === socket) {
                        if (previous == null || current.locked != previous.locked) {
                            withContext(Dispatchers.Main) { notifications.refreshHandler?.invoke() }
                        }
                        sendEvent(
                            WireCodec.message(MessageType.DEVICE_STATUS, identity.id, current)
                        )
                        previous = current
                    }
                    withTimeoutOrNull(5000) { statusWakeup.receive() }
                }
            }
            val clipboardImages = ClipboardImageAssembler()
            socket.soTimeout = 120_000
            try {
                while (!socket.isClosed) {
                    val bytes = WireFrame.read(input)
                    if (active.get() !== socket) break
                    clipboardImages.expire(android.os.SystemClock.elapsedRealtime())
                    if (
                        bytes.contentEquals(
                            "{\"kind\":\"session.ping\"}".toByteArray(Charsets.UTF_8)
                        )
                    ) {
                        writeFrame(socket, "{\"kind\":\"session.pong\"}")
                    } else if (bytes.take(4) == "AAP1".toByteArray(Charsets.US_ASCII).toList()) {
                        callAudio.receive(bytes)
                    } else if (bytes.take(4) == "ACI1".toByteArray(Charsets.US_ASCII).toList()) {
                        val chunk = ClipboardImageChunk.decode(bytes)
                        val image =
                            clipboardImages.accept(chunk, android.os.SystemClock.elapsedRealtime())
                        if (image != null) {
                            val applied = runCatching { features.clipboard.applyImage(image) }
                            if (active.get() === socket)
                                writeFrame(
                                    socket,
                                    WireCodec.encode(
                                        WireCodec.message(
                                            MessageType.COMMAND_RESULT,
                                            identity.id,
                                            CommandResult(
                                                chunk.id,
                                                applied.isSuccess,
                                                if (applied.isSuccess) "Image copied to clipboard"
                                                else
                                                    "Could not apply image: check clipboard helper and unlock the phone",
                                            ),
                                        )
                                    ),
                                )
                        }
                    } else if (bytes.take(4) == "AFC1".toByteArray(Charsets.US_ASCII).toList()) {
                        require(
                            filePackets
                                .trySend(FilePacket.Chunk(socket, FileChunk.decode(bytes)))
                                .isSuccess
                        ) {
                            "File queue full"
                        }
                    } else {
                        val message = WireCodec.decode(bytes.toString(Charsets.UTF_8))
                        require(message.sourceDeviceId == authenticated.deviceId)
                        if (message.type == MessageType.DEVICE_COMMAND) {
                            require(commands.trySend(CommandPacket(socket, message)).isSuccess) {
                                "Command queue full"
                            }
                        } else {
                            require(
                                message.type in
                                    setOf(
                                        MessageType.FILE_OFFER,
                                        MessageType.FILE_ACCEPT,
                                        MessageType.FILE_COMPLETE,
                                        MessageType.FILE_CANCEL,
                                    )
                            )
                            require(
                                filePackets.trySend(FilePacket.Control(socket, message)).isSuccess
                            ) {
                                "File queue full"
                            }
                        }
                    }
                }
            } finally {
                statusJob.cancel()
                clipboardImages.reset()
            }
        } catch (error: Exception) {
            // Authentication material and notification content must never be logged.
            if (dev.androfest.android.BuildConfig.DEBUG) {
                android.util.Log.d(
                    "TwinviaConnection",
                    "Session closed: ${error.javaClass.simpleName}",
                )
                if (error is javax.net.ssl.SSLHandshakeException)
                    android.util.Log.d(
                        "TwinviaConnection",
                        error.message ?: "TLS handshake failed",
                    )
            }
        } finally {
            if (active.compareAndSet(socket, null)) {
                _connected.value = false
                callAudio.stop()
                features.clipboard.setConnected(false)
                handoff.setConnected(false)
                _peerCapabilities.value = emptyList()
                files.disconnected()
                scope.launch(Dispatchers.Main) { if (active.get() == null) features.stopRinging() }
                _status.value =
                    if (saved.get() == null) "Not paired with a Mac"
                    else "Waiting for Mac connection"
            }
            runCatching { socket.close() }
        }
    }

    private fun authenticate(authentication: SessionAuthentication): PairingInvitation {
        return SessionAuthenticator.authenticate(authentication, pending.get(), saved.get())
    }

    private fun sendEvent(event: WireEnvelope) {
        val socket = active.get() ?: return
        runCatching { writeFrame(socket, WireCodec.encode(event)) }
            .onFailure { runCatching { socket.close() } }
    }

    private fun readFrame(input: DataInputStream): String =
        WireFrame.read(input).toString(Charsets.UTF_8)

    private fun writeFrame(socket: SSLSocket, text: String) {
        writePayload(socket, text.toByteArray(Charsets.UTF_8))
    }

    private fun writePayload(socket: SSLSocket, bytes: ByteArray) {
        synchronized(writeLock) {
            WireFrame.write(socket.outputStream, bytes)
        }
    }
}
