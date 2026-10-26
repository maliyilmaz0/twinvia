package dev.androfest.android.core.connection

import javax.net.ssl.SSLSocket
import kotlinx.coroutines.flow.StateFlow

/** Discovery and tunnel admission only. Session authentication belongs to the repository. */
interface PeerLink {
    val status: StateFlow<String>

    fun start()

    fun restart()

    fun permits(socket: SSLSocket): Boolean
}
