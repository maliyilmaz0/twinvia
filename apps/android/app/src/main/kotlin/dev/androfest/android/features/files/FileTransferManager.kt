package dev.androfest.android.features.files

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.os.SystemClock
import android.provider.MediaStore
import dev.twinvia.protocol.*
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.decodeFromJsonElement

data class TransferStatus(
    val fileName: String = "",
    val bytes: Long = 0,
    val total: Long = 0,
    val message: String = "",
    val busy: Boolean = false,
    val receivedUri: Uri? = null,
)

class FileTransferManager(
    private val context: Context,
    private val scope: CoroutineScope,
    private val deviceId: String,
    private val connected: () -> Boolean,
    private val send: (WireEnvelope) -> Unit,
    private val sendChunk: (ByteArray) -> Unit,
) {
    private val mutex = Mutex()
    private var offer: FileOffer? = null
    private var source: InputStream? = null
    private var sink: OutputStream? = null
    private var destination: Uri? = null
    private var digest: MessageDigest? = null
    private var sentEnd = 0L
    private var receivedEnd = 0L
    private var outgoing = false
    @Volatile private var preparing: Job? = null
    private var lastActivity = SystemClock.elapsedRealtime()
    private val _status = MutableStateFlow(TransferStatus())
    val status = _status.asStateFlow()
    private val _incoming = MutableStateFlow<FileOffer?>(null)
    val incoming = _incoming.asStateFlow()

    init {
        scope.launch {
            while (isActive) {
                delay(5000)
                mutex.withLock {
                    val limit = if (_incoming.value != null) 300_000 else 60_000
                    if (
                        _status.value.busy && SystemClock.elapsedRealtime() - lastActivity > limit
                    ) {
                        fail("File transfer timed out.")
                    }
                }
            }
        }
    }

    fun sendFile(file: SelectedFile) {
        scope.launch {
            mutex.withLock {
                if (_status.value.busy) return@withLock
                if (!connected()) {
                    _status.value = TransferStatus(message = "Connect to Mac first.")
                    return@withLock
                }
                preparing = currentCoroutineContext().job
                _status.value =
                    TransferStatus(
                        fileName = file.name,
                        message = "Preparing file",
                        busy = true,
                    )
                lastActivity = SystemClock.elapsedRealtime()
                try {
                    val hash = MessageDigest.getInstance("SHA-256")
                    var size = 0L
                    context.contentResolver.openInputStream(file.uri)?.use { input ->
                        val buffer = ByteArray(65_536)
                        while (true) {
                            currentCoroutineContext().ensureActive()
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (count == 0) continue
                            size += count
                            require(size <= FileChunk.MAX_FILE_BYTES) {
                                "File size limit: 2 GiB."
                            }
                            hash.update(buffer, 0, count)
                        }
                    } ?: error("Could not open the file.")
                    val candidate =
                        FileOffer(
                            UUID.randomUUID().toString(),
                            file.name,
                            file.mimeType,
                            size,
                            hash.digest().hex(),
                        )
                    WireCodec.message(MessageType.FILE_OFFER, deviceId, candidate)
                    source =
                        context.contentResolver.openInputStream(file.uri)
                            ?: error("Could not open the file")
                    offer = candidate
                    outgoing = true
                    sentEnd = 0
                    _status.value =
                        TransferStatus(file.name, 0, size, "Waiting for approval on Mac", true)
                    lastActivity = SystemClock.elapsedRealtime()
                    control(MessageType.FILE_OFFER, candidate)
                } catch (error: Exception) {
                    fail(
                        if (error is CancellationException) "Transfer cancelled."
                        else error.message ?: "Could not prepare the file."
                    )
                } finally {
                    preparing = null
                }
            }
        }
    }

    suspend fun receive(envelope: WireEnvelope) = mutex.withLock {
        try {
            when (envelope.type) {
                MessageType.FILE_OFFER -> {
                    val request =
                        WireCodec.json.decodeFromJsonElement<FileOffer>(envelope.payload).let {
                            it.copy(transferId = it.transferId.lowercase())
                        }
                    if (_status.value.busy || request.size > FileChunk.MAX_FILE_BYTES) {
                        control(
                            MessageType.FILE_CANCEL,
                            FileCancel(
                                request.transferId,
                                "The recipient is busy or the file exceeds 2 GiB.",
                            ),
                        )
                    } else {
                        offer = request
                        outgoing = false
                        _incoming.value = request
                        _status.value =
                            TransferStatus(
                                request.fileName,
                                0,
                                request.size,
                                "Accept incoming file",
                                true,
                            )
                        lastActivity = SystemClock.elapsedRealtime()
                    }
                }
                MessageType.FILE_ACCEPT -> {
                    val ack = WireCodec.json.decodeFromJsonElement<FileAccept>(envelope.payload)
                    val current = offer ?: return@withLock
                    if (!outgoing || !ack.transferId.equals(current.transferId, true))
                        return@withLock
                    require(ack.offset == sentEnd) { "Invalid file location" }
                    lastActivity = SystemClock.elapsedRealtime()
                    _status.value =
                        _status.value.copy(
                            bytes = ack.offset,
                            message =
                                if (ack.offset == current.size) "Mac is verifying the file"
                                else "Sending to Mac",
                        )
                    if (ack.offset < current.size) {
                        val buffer =
                            ByteArray(
                                minOf(FileChunk.MAX_DATA_BYTES.toLong(), current.size - ack.offset)
                                    .toInt()
                            )
                        val count = source!!.read(buffer)
                        require(count > 0) { "The source file changed during transfer." }
                        sentEnd = ack.offset + count
                        sendChunk(
                            FileChunk(current.transferId, ack.offset, buffer.copyOf(count)).encode()
                        )
                    }
                }
                MessageType.FILE_COMPLETE -> {
                    val complete =
                        WireCodec.json.decodeFromJsonElement<FileComplete>(envelope.payload)
                    val current = offer ?: return@withLock
                    if (!outgoing || !complete.transferId.equals(current.transferId, true))
                        return@withLock
                    require(sentEnd == current.size && complete.sha256 == current.sha256) {
                        "File verification failed."
                    }
                    release()
                    _status.value =
                        TransferStatus(
                            current.fileName,
                            current.size,
                            current.size,
                            "Sent to Mac · SHA-256 verified",
                        )
                }
                MessageType.FILE_CANCEL -> {
                    val cancel = WireCodec.json.decodeFromJsonElement<FileCancel>(envelope.payload)
                    if (cancel.transferId.equals(offer?.transferId, true))
                        fail(
                            cancel.reason ?: "The other device cancelled the transfer.",
                            notify = false,
                        )
                }
                else -> Unit
            }
        } catch (error: Exception) {
            fail(error.message ?: "Could not complete the file transfer.")
        }
    }

    suspend fun receiveChunk(chunk: FileChunk) = mutex.withLock {
        try {
            val current = offer ?: return@withLock
            if (!chunk.transferId.equals(current.transferId, true)) return@withLock
            require(!outgoing && sink != null)
            require(chunk.offset == receivedEnd && receivedEnd + chunk.data.size <= current.size) {
                "Invalid file chunk"
            }
            sink!!.write(chunk.data)
            digest!!.update(chunk.data)
            receivedEnd += chunk.data.size
            lastActivity = SystemClock.elapsedRealtime()
            _status.value = _status.value.copy(bytes = receivedEnd, message = "Receiving from Mac")
            if (receivedEnd == current.size) finishIncoming()
            else control(MessageType.FILE_ACCEPT, FileAccept(current.transferId, receivedEnd))
        } catch (error: Exception) {
            fail(error.message ?: "Could not save the file.")
        }
    }

    fun accept() = scope.launch {
        mutex.withLock {
            val current = _incoming.value ?: return@withLock
            try {
                val available = (context.getExternalFilesDir(null) ?: context.filesDir).usableSpace
                require(available > current.size + 16_777_216) {
                    "Not enough free space on the phone."
                }
                val values =
                    ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, current.fileName)
                        put(MediaStore.Downloads.MIME_TYPE, current.mimeType)
                        put(
                            MediaStore.Downloads.RELATIVE_PATH,
                            Environment.DIRECTORY_DOWNLOADS + "/Twinvia",
                        )
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                destination =
                    context.contentResolver.insert(
                        MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                        values,
                    ) ?: error("Could not create the download.")
                sink =
                    context.contentResolver.openOutputStream(destination!!, "w")
                        ?: error("Could not open the file.")
                digest = MessageDigest.getInstance("SHA-256")
                receivedEnd = 0
                _incoming.value = null
                lastActivity = SystemClock.elapsedRealtime()
                _status.value = _status.value.copy(message = "Receiving from Mac")
                control(MessageType.FILE_ACCEPT, FileAccept(current.transferId, 0))
                if (current.size == 0L) finishIncoming()
            } catch (error: Exception) {
                fail(error.message ?: "Could not accept the file.")
            }
        }
    }

    fun cancel() {
        preparing?.cancel()
        scope.launch { mutex.withLock { fail("Transfer cancelled.") } }
    }

    suspend fun disconnected() {
        preparing?.cancel()
        mutex.withLock {
            if (_status.value.busy) fail("Disconnected; the file is incomplete.", notify = false)
        }
    }

    private fun finishIncoming() {
        val current = offer!!
        require(digest!!.digest().hex() == current.sha256) {
            "SHA-256 mismatch; incomplete file removed."
        }
        sink!!.close()
        sink = null
        val uri = destination!!
        val storedHash = MessageDigest.getInstance("SHA-256")
        var storedSize = 0L
        context.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(65_536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                storedSize += count
                require(storedSize <= current.size) { "The saved file size changed." }
                storedHash.update(buffer, 0, count)
            }
        } ?: error("Could not open the saved file.")
        require(storedSize == current.size && storedHash.digest().hex() == current.sha256) {
            "The saved file failed verification."
        }
        val updated =
            context.contentResolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null,
            )
        require(updated == 1) { "Could not publish the file." }
        destination = null
        release()
        _status.value =
            TransferStatus(
                current.fileName,
                current.size,
                current.size,
                "Saved in Downloads/Twinvia · SHA-256 verified",
                receivedUri = uri,
            )
        // Success only after the receiver verified and published the full file.
        runCatching {
            control(MessageType.FILE_COMPLETE, FileComplete(current.transferId, current.sha256))
        }
    }

    private fun fail(reason: String, notify: Boolean = true) {
        val current = offer
        val previous = _status.value
        release()
        _status.value = previous.copy(message = reason.take(256), busy = false)
        if (notify && current != null)
            runCatching {
                val points = reason.codePoints().limit(128).toArray()
                control(
                    MessageType.FILE_CANCEL,
                    FileCancel(current.transferId, String(points, 0, points.size)),
                )
            }
    }

    private fun release() {
        runCatching { source?.close() }
        source = null
        runCatching { sink?.close() }
        sink = null
        destination?.let { runCatching { context.contentResolver.delete(it, null, null) } }
        destination = null
        digest = null
        offer = null
        _incoming.value = null
        outgoing = false
        sentEnd = 0
        receivedEnd = 0
    }

    private inline fun <reified T> control(type: MessageType, value: T) =
        send(WireCodec.message(type, deviceId, value))

    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }
}
