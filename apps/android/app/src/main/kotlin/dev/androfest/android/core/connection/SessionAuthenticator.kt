package dev.androfest.android.core.connection

import dev.twinvia.protocol.PairingInvitation
import dev.twinvia.protocol.SessionAuthentication
import java.security.MessageDigest

/** Pure session policy. Persistent trust is committed by the repository after this succeeds. */
object SessionAuthenticator {
    fun authenticate(
        authentication: SessionAuthentication,
        pending: PairingInvitation?,
        saved: PairingInvitation?,
        now: Long = System.currentTimeMillis(),
    ): PairingInvitation {
        val invitation = pending?.takeIf { it.expiresAt > now } ?: saved
        require(
            invitation != null &&
                authentication.kind == "session.auth" &&
                authentication.version == 1
        )
        require(
            authentication.capabilities.size <= 32 &&
                authentication.capabilities.all { it.length in 1..128 }
        )
        require(
            authentication.invitationId == invitation.id &&
                authentication.deviceId == invitation.deviceId
        )
        require(
            MessageDigest.isEqual(
                authentication.secret.toByteArray(Charsets.UTF_8),
                invitation.secret.toByteArray(Charsets.UTF_8),
            )
        )
        return invitation
    }
}
