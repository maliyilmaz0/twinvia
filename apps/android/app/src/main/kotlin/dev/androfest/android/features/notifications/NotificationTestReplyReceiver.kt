package dev.androfest.android.features.notifications

import android.app.NotificationManager
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dev.androfest.android.AndrofestApplication

/** A local demonstration reply. No SMS or third party message is sent. */
class NotificationTestReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reply =
            RemoteInput.getResultsFromIntent(intent)?.getCharSequence("demo-reply")?.toString()
                ?: return
        if (reply.isBlank() || reply.length > 4096) return
        (context.applicationContext as AndrofestApplication).notifications.recordTestReply(reply)
        context.getSystemService(NotificationManager::class.java).cancel(1001)
    }
}
