package dev.androfest.android.features.clipboard

import android.app.KeyguardManager
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Process
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject

/**
 * Loopback-only IPC with mutual challenge/HMAC authentication. Cross-device data uses pinned TLS.
 */
class AutomaticClipboard(private val context: Context, private val scope: CoroutineScope) {
    private val preferences = context.getSharedPreferences("clipboard-sync", Context.MODE_PRIVATE)
    private val _enabled = MutableStateFlow(preferences.getBoolean("enabled", true))
    val enabled = _enabled.asStateFlow()
    private val _ready = MutableStateFlow(false)
    val ready = _ready.asStateFlow()
    private val _status = MutableStateFlow("Waiting for background clipboard helper")
    val status = _status.asStateFlow()
    var onChanged: ((String) -> Unit)? = null
    @Volatile private var connected = false
    @Volatile private var peer: Socket? = null
    @Volatile private var output: DataOutputStream? = null
    private val writeLock = Any()
    @Volatile private var lastAppliedText: String? = null
    private var configured: Boolean? = null
    @Volatile private var changesSent = 0
    @Volatile private var changesApplied = 0
    @Volatile private var helperSessions = 0
    @Volatile private var bridgeReconnects = 0

    init {
        scope.launch(Dispatchers.IO) {
            // The shell helper learns this port during USB activation and cannot
            // follow an app-only fallback to another ephemeral port. Preserve it
            // across process/service restarts and wait for the old socket to be
            // released instead of silently stranding the helper.
            val server = bindStableServer()
            preferences.edit().putInt("port", server.localPort).apply()
            val secret =
                preferences.getString("secret", null)
                    ?: randomHex(32).also {
                        preferences.edit().putString("secret", it).commit()
                    }
            java.io
                .File(context.filesDir, "clipboard-helper.json")
                .writeText(
                    JSONObject()
                        .put("uid", Process.myUid())
                        .put("port", server.localPort)
                        .put("secret", secret)
                        .toString()
                )
            server.use {
                while (isActive) {
                    val socket = server.accept()
                    try {
                        socket.soTimeout = 3000
                        val input = DataInputStream(socket.inputStream)
                        val stream = DataOutputStream(socket.outputStream)
                        val challenge = randomHex(16)
                        write(stream, JSONObject().put("kind", "challenge").put("nonce", challenge))
                        val size = input.readInt()
                        require(size in 1..1024)
                        val auth =
                            JSONObject(
                                String(ByteArray(size).also(input::readFully), Charsets.UTF_8)
                            )
                        val nonce = auth.getString("nonce")
                        require(
                            auth.getString("kind") == "authenticate" &&
                                nonce.matches(Regex("[a-f0-9]{32}"))
                        )
                        val expected =
                            proof(secret, "androfest.clipboard.helper.v1\n$challenge\n$nonce")
                        require(
                            MessageDigest.isEqual(
                                expected.toByteArray(),
                                auth.getString("proof").toByteArray(),
                            )
                        )
                        write(
                            stream,
                            JSONObject()
                                .put("kind", "authenticated")
                                .put(
                                    "proof",
                                    proof(secret, "androfest.clipboard.app.v1\n$challenge\n$nonce"),
                                ),
                        )
                        socket.soTimeout = 0
                        synchronized(writeLock) {
                            peer = socket
                            output = stream
                        }
                        helperSessions++
                        while (isActive) {
                            val size = input.readInt()
                            require(size in 1..131_072)
                            val bytes = ByteArray(size).also(input::readFully)
                            val message = JSONObject(String(bytes, Charsets.UTF_8))
                            when (message.getString("kind")) {
                                "ready" -> {
                                    require(message.getInt("version") == 1)
                                    _ready.value = true
                                    configured = null
                                    configure()
                                }
                                "changed" -> {
                                    val text = message.getString("text")
                                    require(text.isNotEmpty() && text.length <= 16_384)
                                    if (text == lastAppliedText) {
                                        lastAppliedText = null
                                    } else if (allowed()) {
                                        changesSent++
                                        onChanged?.invoke(text)
                                    }
                                }
                                "applied" ->
                                    Unit // Older helpers may acknowledge an in-flight write.
                                else -> error("Unknown helper message")
                            }
                        }
                    } catch (error: Exception) {
                        if (error is CancellationException) throw error
                    } finally {
                        _ready.value = false
                        lastAppliedText = null
                        configured = null
                        synchronized(writeLock) {
                            output = null
                            peer = null
                        }
                        runCatching { socket.close() }
                        _status.value = "Waiting for background clipboard helper"
                    }
                }
            }
        }
        scope.launch(Dispatchers.IO) {
            while (isActive) {
                configure()
                if (dev.androfest.android.BuildConfig.DEBUG) {
                    runCatching {
                        java.io
                            .File(context.filesDir, "clipboard-status.json")
                            .writeText(JSONObject(diagnostics()).toString())
                    }
                }
                delay(500)
            }
        }
    }

    fun setEnabled(value: Boolean) {
        preferences.edit().putBoolean("enabled", value).apply()
        _enabled.value = value
        scope.launch(Dispatchers.IO) { configure() }
    }

    @Synchronized
    fun setConnected(value: Boolean) {
        val previous = connected
        connected = value
        if (value && !previous) {
            bridgeReconnects++
            // A NAN/TLS reconnect is a new bridge epoch. Re-authenticate the
            // loopback helper too so a half-open Binder listener or socket from
            // the previous epoch cannot leave clipboard changes stuck forever.
            synchronized(writeLock) {
                _ready.value = false
                configured = null
                output = null
                peer?.let { runCatching { it.close() } }
                peer = null
            }
            _status.value = "Reconnecting clipboard helper for phone-to-Mac copies"
        }
        scope.launch(Dispatchers.IO) { configure() }
    }

    private fun allowed() =
        _enabled.value &&
            connected &&
            !context.getSystemService(KeyguardManager::class.java).isDeviceLocked

    private suspend fun bindStableServer(): ServerSocket {
        val address = InetAddress.getByName("127.0.0.1")
        val port = preferences.getInt("port", 0)
        while (currentCoroutineContext().isActive) {
            val server = ServerSocket().apply { reuseAddress = true }
            try {
                server.bind(InetSocketAddress(address, port))
                return server
            } catch (failure: Exception) {
                runCatching { server.close() }
                if (failure is CancellationException) throw failure
                _status.value = "Restarting clipboard helper"
                delay(1_000)
            }
        }
        throw CancellationException("Clipboard server stopped")
    }

    @Synchronized
    private fun configure() {
        val allow = allowed()
        _status.value =
            when {
                !_enabled.value -> "Automatic clipboard sync disabled"
                !connected -> "Clipboard sync waiting for Mac"
                !allow -> "Phone locked · Clipboard sync paused"
                !_ready.value -> "Mac-to-phone clipboard ready · Phone-to-Mac needs helper or Share"
                else -> "Automatic clipboard sync enabled"
            }
        if (!_ready.value || configured == allow) return
        try {
            send(JSONObject().put("kind", "configure").put("enabled", allow))
            configured = allow
        } catch (_: Exception) {
            peer?.let { runCatching { it.close() } }
        }
    }

    private fun send(value: JSONObject) =
        synchronized(writeLock) {
            val stream = output ?: error("Background clipboard helper disconnected")
            write(stream, value)
        }

    private fun write(stream: DataOutputStream, value: JSONObject) {
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        require(bytes.size <= 131_072)
        stream.writeInt(bytes.size)
        stream.write(bytes)
        stream.flush()
    }

    private fun randomHex(count: Int) =
        ByteArray(count)
            .also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it) }

    private fun proof(secret: String, text: String): String {
        val key = secret.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
        return Mac.getInstance("HmacSHA256")
            .apply { init(SecretKeySpec(key, "HmacSHA256")) }
            .doFinal(text.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    suspend fun apply(text: String) {
        check(allowed()) { "Clipboard sync disabled or phone locked" }
        require(text.isNotEmpty() && text.length <= 16_384)
        withContext(Dispatchers.Main.immediate) {
            check(allowed())
            lastAppliedText = if (_ready.value) text else null
            try {
                context
                    .getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("Twinvia", text))
                changesApplied++
            } catch (failure: Exception) {
                lastAppliedText = null
                throw failure
            }
        }
    }

    suspend fun applyImage(png: ByteArray) =
        withContext(Dispatchers.IO) {
            check(allowed()) { "Clipboard sync disabled or phone locked" }
            require(png.size in 1..dev.twinvia.protocol.ClipboardImageChunk.MAX_IMAGE_BYTES)
            require(png.take(8) == byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10).toList())
            val bounds =
                android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeByteArray(png, 0, png.size, bounds)
            require(
                bounds.outWidth in 1..8192 &&
                    bounds.outHeight in 1..8192 &&
                    bounds.outWidth.toLong() * bounds.outHeight <= 16_777_216
            ) {
                "Image limit: 16 megapixels"
            }
            val directory = java.io.File(context.cacheDir, "clipboard-images").apply { mkdirs() }
            val id = UUID.randomUUID().toString()
            val file = java.io.File(directory, "$id.png")
            file.writeBytes(png)
            val uri =
                androidx.core.content.FileProvider.getUriForFile(
                    context,
                    "${context.packageName}.clipboard",
                    file,
                )
            try {
                withContext(Dispatchers.Main.immediate) {
                    check(allowed())
                    val clip =
                        ClipData(
                            ClipDescription("Twinvia image", arrayOf("image/png")),
                            ClipData.Item(uri),
                        )
                    context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
                    changesApplied++
                }
                // Keep the current and two previous images so paste consumers can finish reads.
                directory
                    .listFiles()
                    ?.filter { it != file }
                    ?.sortedByDescending { it.lastModified() }
                    ?.drop(2)
                    ?.forEach {
                        it.delete()
                    }
            } catch (failure: Exception) {
                file.delete()
                throw failure
            }
        }

    fun diagnostics(): Map<String, Any> =
        mapOf(
            "enabled" to _enabled.value,
            "helperReady" to _ready.value,
            "connected" to connected,
            "sent" to changesSent,
            "applied" to changesApplied,
            "helperSessions" to helperSessions,
            "bridgeReconnects" to bridgeReconnects,
        )
}
