package dev.androfest.android.core.connection

import dev.androfest.protocol.*
import org.junit.Assert.*
import org.junit.Test

class SessionAuthenticatorTest {
    private val now = 1_800_000_000_000L
    private val invitation =
        PairingInvitation(
            version = 2,
            id = "da83b21c-0e54-4b8a-acbe-e174384c5765",
            deviceId = "b82283ab-1934-467d-bb6d-a90fbb35083f",
            name = "Test Mac",
            secret = "ab".repeat(32),
            expiresAt = now + 1000,
        )

    private fun auth(value: PairingInvitation = invitation) =
        SessionAuthentication(
            invitationId = value.id,
            deviceId = value.deviceId,
            secret = value.secret,
        )

    @Test
    fun validPendingAndExpiredSavedTrustHaveDifferentLifetimes() {
        assertSame(invitation, SessionAuthenticator.authenticate(auth(), invitation, null, now))
        val expired = invitation.copy(expiresAt = now - 1)
        assertSame(expired, SessionAuthenticator.authenticate(auth(expired), null, expired, now))
        assertThrows(IllegalArgumentException::class.java) {
            SessionAuthenticator.authenticate(auth(expired), expired, null, now)
        }
    }

    @Test
    fun wrongSecretIdentityAndProtocolAreRejected() {
        for (invalid in
            listOf(
                auth().copy(secret = "0".repeat(64)),
                auth().copy(deviceId = "wrong"),
                auth().copy(invitationId = "wrong"),
                auth().copy(version = 2),
                auth().copy(kind = "unknown"),
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                SessionAuthenticator.authenticate(invalid, invitation, null, now)
            }
        }
    }

    @Test
    fun capabilityBoundsAndExpiredPendingFallbackAreEnforced() {
        for (caps in listOf(List(33) { "x" }, listOf(""), listOf("x".repeat(129)))) {
            assertThrows(IllegalArgumentException::class.java) {
                SessionAuthenticator.authenticate(
                    auth().copy(capabilities = caps),
                    invitation,
                    null,
                    now,
                )
            }
        }
        assertSame(
            invitation,
            SessionAuthenticator.authenticate(
                auth(),
                invitation.copy(expiresAt = now),
                invitation,
                now,
            ),
        )
    }
}
