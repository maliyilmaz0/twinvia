package dev.androfest.android.features.updates

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
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
    val installing: Boolean = false,
)

class AppUpdater(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null
    private var manifest: UpdateManifest? = null
    private var apk: File? = null
    private var pendingConfirmation: Intent? = null
    private val _state = MutableStateFlow(UpdateState())
    val state = _state.asStateFlow()
    private val preferences = context.getSharedPreferences("updates", Context.MODE_PRIVATE)
    var checkOnLaunch: Boolean
        get() = preferences.getBoolean("checkOnLaunch", false)
        set(value) {
            preferences.edit().putBoolean("checkOnLaunch", value).apply()
        }

    init {
        if (UpdateInstaller.activeSession(context) != null) {
            _state.value =
                UpdateState(
                    "An installation is pending. Cancel it to retry if confirmation was interrupted.",
                    installing = true,
                )
        } else if (checkOnLaunch) check()
    }

    fun check() =
        launch("Checking for updates…") {
            check(UpdateInstaller.activeSession(context) == null) {
                "Finish the pending installation first."
            }
            pendingConfirmation = null
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
            pendingConfirmation?.let { confirmation ->
                activity.startActivity(confirmation)
                pendingConfirmation = null
                return@launch
            }
            check(UpdateInstaller.activeSession(context) == null) {
                "Waiting for Android installation confirmation."
            }
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
                _state.value =
                    UpdateState(
                        "Waiting for Android. Select Continue installation when confirmation is ready.",
                        version = next.version,
                        installing = true,
                    )
                withContext(Dispatchers.IO) {
                    UpdateInstaller.stage(context, file, next.android.size)
                }
            }
        }

    fun cancelInstallation() {
        UpdateInstaller.cancel(context)
        pendingConfirmation = null
        _state.value = UpdateState("Installation canceled. Check for updates to retry.")
    }

    internal fun installationResult(intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                pendingConfirmation =
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                _state.value =
                    _state.value.copy(
                        message = "Android confirmation is ready. Select Continue installation.",
                        ready = pendingConfirmation != null,
                        installing = true,
                        version = _state.value.version ?: "update",
                    )
            }
            PackageInstaller.STATUS_SUCCESS -> {
                pendingConfirmation = null
                _state.value = UpdateState("Update installed. Reopen Twinvia to continue.")
            }
            else -> {
                pendingConfirmation = null
                _state.value =
                    UpdateState(
                        "Installation was canceled or rejected. Check for updates to retry."
                    )
            }
        }
    }

    private fun validate(file: File, next: UpdateManifest) {
        check(file.length() == next.android.size) { "Update size mismatch." }
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
        fun signers(info: android.content.pm.PackageInfo) =
            info.signingInfo?.apkContentsSigners?.map { it.toCharsString() }?.toSet() ?: emptySet()
        UpdatePolicy.validateApkIdentity(
            context.packageName,
            installed.longVersionCode,
            candidate.packageName,
            candidate.longVersionCode,
            next.build,
            signers(installed),
            signers(candidate),
        )
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
