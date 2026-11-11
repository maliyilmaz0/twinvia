package dev.androfest.android.features.updates

import android.app.Instrumentation
import android.content.Intent
import android.os.Bundle
import dev.androfest.android.BuildConfig
import dev.androfest.android.MainActivity
import dev.androfest.android.TwinviaApplication
import java.io.File

/** ADB-authorized test APK only. This class is never part of the application APK. */
class UpdateDeviceValidation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        try {
            val folder = File(targetContext.cacheDir, "updates/device-validation")
            val manifest =
                UpdatePolicy.verify(
                    File(folder, "manifest.json").readBytes(),
                    File(folder, "manifest.sig").readText(),
                    BuildConfig.UPDATE_PUBLIC_KEY,
                )
            val apk = File(folder, "candidate.apk")
            lateinit var updater: AppUpdater
            runOnMainSync {
                updater = (targetContext.applicationContext as TwinviaApplication).updates
            }
            // Exercise the installed baseline's private validator without adding a production
            // intent or an exported API that can trigger installation.
            val validate =
                AppUpdater::class
                    .java
                    .getDeclaredMethod("validate", File::class.java, UpdateManifest::class.java)
            validate.isAccessible = true
            validate.invoke(updater, apk, manifest)
            UpdateInstaller.cancel(targetContext)
            AppUpdater::class
                .java
                .getDeclaredField("manifest")
                .apply { isAccessible = true }
                .set(updater, manifest)
            AppUpdater::class
                .java
                .getDeclaredField("apk")
                .apply { isAccessible = true }
                .set(updater, apk)
            val activity =
                startActivitySync(
                    Intent(targetContext, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            runOnMainSync { updater.install(activity) }
            sendStatus(
                0,
                Bundle().apply {
                    putString(
                        "phase",
                        "Verified update action requested; foreground/system confirmation required",
                    )
                },
            )
            // An actual package upgrade terminates this instrumentation with its old process.
            // The host verifies the new installed build, signer and preserved trust separately.
            Thread.sleep(600_000)
            finish(
                0,
                Bundle().apply {
                    putString(
                        "phase",
                        "Confirmation was not completed within the validation window",
                    )
                },
            )
        } catch (_: Exception) {
            finish(
                1,
                Bundle().apply {
                    putString("error", "Update validation/staging failed; no data was removed")
                },
            )
        }
    }
}
