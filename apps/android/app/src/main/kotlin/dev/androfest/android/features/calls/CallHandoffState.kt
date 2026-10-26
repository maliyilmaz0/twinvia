package dev.androfest.android.features.calls

import java.util.UUID

/** One consent and identity per cellular call. No caller identity is retained. */
data class HandoffSnapshot(
    val state: String = "idle",
    val token: String? = null,
    val approval: String? = null,
)

class CallHandoffState {
    var snapshot = HandoffSnapshot()
        private set

    fun transition(state: String): Boolean {
        require(state in setOf("idle", "ringing", "active"))
        if (state == snapshot.state) return false
        snapshot =
            if (state == "idle") HandoffSnapshot()
            else
                snapshot.copy(
                    state = state,
                    token = snapshot.token ?: UUID.randomUUID().toString(),
                )
        return true
    }

    fun approve(token: String) {
        check(snapshot.token == token && snapshot.state != "idle") {
            "This call is no longer valid"
        }
        snapshot = snapshot.copy(approval = UUID.randomUUID().toString())
    }

    fun revoke(token: String? = snapshot.token) {
        check(token == snapshot.token) { "This call is no longer valid" }
        snapshot = snapshot.copy(approval = null)
    }
}
