package dev.androfest.android.features.updates

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import dev.androfest.android.BuildConfig
import java.io.File
import java.net.URL
import java.security.MessageDigest
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class UpdateState(
    val message: String = "Updates come from signed GitHub releases.",
    val busy: Boolean = false,
    val version: String? = null,
    val ready: Boolean = false,
)

class AppUpdater(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private var manifest: UpdateManifest? = null
    private var apk: File? = null
    private val _state = MutableStateFlow(UpdateState())
    val state = _state.asStateFlow()
    private val preferences = context.getSharedPreferences("updates", Context.MODE_PRIVATE)
    var checkOnLaunch: Boolean
        get() = preferences.getBoolean("checkOnLaunch", false)
        set(value) {
            preferences.edit().putBoolean("checkOnLaunch", value).apply()
        }

    init {
        if (checkOnLaunch) check()
    }

    fun check() =
        launch("Checking for updates…") {
            val base = "https://github.com/maliyilmaz0/twinvia/releases/latest/download/"
            val bytes = fetch(base + "update-manifest.json", 65_536)
            val signature = fetch(base + "update-manifest.sig", 256).decodeToString()
            val next = UpdatePolicy.verify(bytes, signature, BuildConfig.UPDATE_PUBLIC_KEY)
            val current =
                context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode
            manifest = next.takeIf { it.build > current }
            apk = null
            _state.value =
                if (manifest == null) UpdateState("Twinvia is up to date.")
                else UpdateState("Twinvia ${next.version} is available.", version = next.version)
        }

    fun download() =
        launch("Downloading verified update…") {
            val next = requireNotNull(manifest)
            val directory = File(context.cacheDir, "updates").apply { mkdirs() }
            val partial = File(directory, "update.part")
            val target = File(directory, "Twinvia-${next.version}.apk")
            try {
                withContext(Dispatchers.IO) {
                    connection(next.android.url).let { connection ->
                        try {
                            connection.inputStream.use { input ->
                                partial.outputStream().use { output ->
                                    val buffer = ByteArray(64 * 1024)
                                    var received = 0L
                                    while (true) {
                                        currentCoroutineContext().ensureActive()
                                        val count = input.read(buffer)
                                        if (count < 0) break
                                        received += count
                                        check(received <= next.android.size) {
                                            "Update exceeds its signed size."
                                        }
                                        output.write(buffer, 0, count)
                                    }
                                    check(received == next.android.size) {
                                        "Incomplete update download."
                                    }
                                }
                            }
                        } finally {
                            connection.disconnect()
                        }
                    }
                    validate(partial, next)
                    partial.copyTo(target, overwrite = true)
                }
                apk = target
                _state.value =
                    UpdateState(
                        "Update verified. Android will ask you to confirm installation.",
                        version = next.version,
                        ready = true,
                    )
            } finally {
                withContext(NonCancellable + Dispatchers.IO) { partial.delete() }
            }
        }

    fun install(activity: Context) =
        launch("Preparing Android installer…") {
            val file = requireNotNull(apk)
            val next = requireNotNull(manifest)
            withContext(Dispatchers.IO) { validate(file, next) }
            if (!context.packageManager.canRequestPackageInstalls()) {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${context.packageName}"),
                    )
                )
                _state.value =
                    UpdateState(
                        "Allow updates from Twinvia, then return and select Install update.",
                        version = next.version,
                        ready = true,
                    )
            } else {
                val uri =
                    FileProvider.getUriForFile(context, "${context.packageName}.clipboard", file)
                activity.startActivity(
                    Intent(Intent.ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                )
                _state.value =
                    UpdateState(
                        "Confirm installation in Android's installer.",
                        version = next.version,
                        ready = true,
                    )
            }
        }

    private fun validate(file: File, next: UpdateManifest) {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val bytes = ByteArray(65_536)
            while (true) {
                val n = input.read(bytes)
                if (n < 0) break
                digest.update(bytes, 0, n)
            }
        }
        check(digest.digest().joinToString("") { "%02x".format(it) } == next.android.sha256) {
            "Update checksum mismatch."
        }
        val flags =
            PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong())
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        val candidate =
            context.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("Invalid APK.")
        check(
            candidate.packageName == context.packageName &&
                candidate.longVersionCode == next.build &&
                candidate.longVersionCode > installed.longVersionCode
        ) {
            "APK identity/version mismatch."
        }
        fun signers(info: android.content.pm.PackageInfo) =
            info.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet()
        val trusted = signers(installed)
        check(!trusted.isNullOrEmpty() && trusted == signers(candidate)) {
            "This APK uses a different signing certificate. The installed preview cannot be updated with it; your data has been preserved."
        }
    }

    private fun launch(message: String, operation: suspend () -> Unit) {
        if (job?.isActive == true) return
        _state.value = _state.value.copy(message = message, busy = true)
        job = scope.launch {
            try {
                operation()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                _state.value = _state.value.copy(message = error.message ?: "Update failed.")
            } finally {
                _state.value = _state.value.copy(busy = false)
            }
        }
    }

    private fun connection(url: String) =
        (URL(url).openConnection() as javax.net.ssl.HttpsURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            setRequestProperty("User-Agent", "Twinvia/${BuildConfig.VERSION_NAME}")
        }

    private suspend fun fetch(url: String, limit: Int): ByteArray =
        withContext(Dispatchers.IO) {
            val connection = connection(url)
            try {
                if (connection.responseCode == 404)
                    error("No signed stable update is published yet.")
                check(connection.responseCode == 200) {
                    "Update server returned ${connection.responseCode}."
                }
                connection.inputStream.use { input ->
                    val bytes = input.readNBytes(limit + 1)
                    check(bytes.size <= limit) { "Update metadata exceeds its limit." }
                    bytes
                }
            } finally {
                connection.disconnect()
            }
        }
}
