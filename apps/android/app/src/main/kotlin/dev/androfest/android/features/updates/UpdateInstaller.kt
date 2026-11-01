package dev.androfest.android.features.updates

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import dev.androfest.android.TwinviaApplication
import java.io.File

/** Copies verified bytes into an OS-owned, self-update-only session; no APK URI is shared. */
internal object UpdateInstaller {
    private const val ACTION = "dev.twinvia.UPDATE_INSTALL_RESULT"
    private const val SESSION = "installationSession"

    private fun preferences(context: Context) =
        context.getSharedPreferences("updates", Context.MODE_PRIVATE)

    fun activeSession(context: Context): Int? {
        val id = preferences(context).getInt(SESSION, -1)
        if (id < 0) return null
        if (context.packageManager.packageInstaller.getSessionInfo(id) != null) return id
        preferences(context).edit().remove(SESSION).apply()
        return null
    }

    fun cancel(context: Context) {
        activeSession(context)?.let { id ->
            runCatching { context.packageManager.packageInstaller.abandonSession(id) }
        }
        preferences(context).edit().remove(SESSION).apply()
    }

    fun stage(context: Context, file: File, size: Long) {
        val installer = context.packageManager.packageInstaller
        val params =
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                setAppPackageName(context.packageName)
                setSize(size)
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
            }
        val id = installer.createSession(params)
        try {
            installer.openSession(id).use { session ->
                session.openWrite("base.apk", 0, size).use { output ->
                    file.inputStream().use { it.copyTo(output) }
                    session.fsync(output)
                }
                check(preferences(context).edit().putInt(SESSION, id).commit())
                // PackageInstaller supplies status extras; an explicit non-exported receiver
                // contains the necessary mutable PendingIntent to this installation only.
                val callback =
                    PendingIntent.getBroadcast(
                        context,
                        id,
                        Intent(context, UpdateInstallReceiver::class.java).setAction(ACTION),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                    )
                session.commit(callback.intentSender)
            }
        } catch (error: Exception) {
            runCatching { installer.abandonSession(id) }
            preferences(context).edit().remove(SESSION).apply()
            throw error
        }
    }

    fun acceptResult(context: Context, intent: Intent): Boolean {
        val id = preferences(context).getInt(SESSION, -1)
        if (
            intent.action != ACTION ||
                id < 0 ||
                intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -2) != id
        )
            return false
        if (
            intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE) !=
                PackageInstaller.STATUS_PENDING_USER_ACTION
        ) {
            preferences(context).edit().remove(SESSION).apply()
        }
        return true
    }
}

/** The foreground update panel opens the confirmation only after another explicit tap. */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (UpdateInstaller.acceptResult(context, intent)) {
            (context.applicationContext as TwinviaApplication).updates.installationResult(intent)
        }
    }
}
