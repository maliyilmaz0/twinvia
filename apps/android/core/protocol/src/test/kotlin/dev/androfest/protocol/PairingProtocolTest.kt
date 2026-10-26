package dev.androfest.protocol

import kotlinx.serialization.Serializable
import org.junit.Assert.*
import org.junit.Test

class PairingProtocolTest {
    @Serializable
    private data class Fixture(
        val invitation: PairingInvitation,
        val introduction: PairingIntroduction,
        val link: String,
    )

    private val fixture
        get() =
            WireCodec.json.decodeFromString<Fixture>(
                requireNotNull(javaClass.classLoader?.getResource("pairing/handshake.json"))
                    .readText()
            )

    private val now = 1792188000000L

    @Test
    fun `independently generated HMAC fixture authenticates`() {
        val f = fixture
        assertTrue(f.introduction.verify(f.invitation, now))
        assertEquals(f.invitation, PairingInvitation.fromLink(f.link, now))
    }

    @Test
    fun `endpoint or certificate tampering rejected`() {
        val f = fixture
        assertFalse(f.introduction.copy(port = 12345).verify(f.invitation, now))
        assertFalse(f.introduction.copy(fingerprint = "d4".repeat(32)).verify(f.invitation, now))
        assertFalse(f.introduction.copy(deviceId = f.invitation.deviceId).verify(f.invitation, now))
    }

    @Test
    fun `wrong QR secret and stale introductions rejected`() {
        val f = fixture
        assertFalse(f.introduction.verify(f.invitation.copy(secret = "d4".repeat(32)), now))
        assertFalse(f.introduction.verify(f.invitation, now + 90_001))
        assertFalse(f.introduction.verify(f.invitation, now - 90_001))
    }

    @Test
    fun `expired QR cannot create a new pairing`() {
        val f = fixture
        assertThrows(IllegalArgumentException::class.java) { f.invitation.validate(now + 300_001) }
        f.invitation.validate(now + 300_001, allowExpired = true)
    }

    @Test
    fun `public network destination and malformed links rejected`() {
        val f = fixture
        assertThrows(IllegalArgumentException::class.java) {
            f.invitation.copy(host = "8.8.8.8").validate(now)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PairingInvitation.fromLink("https://example.com", now)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PairingInvitation.fromLink("x".repeat(4097), now)
        }
    }

    @Serializable private data class NativeVector(val compactIntroduction: String)

    @Serializable
    private data class NativePairingVector(
        val invitation: PairingInvitation,
        val introduction: PairingIntroduction,
        val link: String,
        val compactIntroduction: String,
    )

    @Test
    fun `address free pairing authenticates and isolates discovery`() {
        val f =
            WireCodec.json.decodeFromString<NativePairingVector>(
                requireNotNull(javaClass.classLoader?.getResource("pairing/native-pairing.json"))
                    .readText()
            )
        assertEquals(f.invitation, PairingInvitation.fromLink(f.link, now))
        assertEquals(2, f.invitation.version)
        assertNull(f.invitation.host)
        assertNull(f.invitation.port)
        assertTrue(f.introduction.verify(f.invitation, now))
        assertArrayEquals(
            java.util.Base64.getDecoder().decode(f.compactIntroduction),
            PairingIntroductionCodec.encodeIntroduction(f.introduction),
        )
        assertThrows(IllegalArgumentException::class.java) {
            PairingInvitation.fromLink(f.link, now + 300_001)
        }
        assertThrows(IllegalArgumentException::class.java) {
            f.invitation.copy(host = "192.168.1.1", port = 45311).validate(now)
        }
        assertThrows(IllegalArgumentException::class.java) {
            f.invitation.copy(version = 3).validate(now)
        }
        assertFalse(f.introduction.verify(f.invitation.copy(secret = "d4".repeat(32)), now))
        f.invitation.validate(now + 300_001, allowExpired = true)
    }

    @Test
    fun `compact introduction matches independent vector`() {
        val vector =
            WireCodec.json.decodeFromString<NativeVector>(
                requireNotNull(javaClass.classLoader?.getResource("pairing/native-peer.json"))
                    .readText()
            )
        val f = fixture
        assertArrayEquals(
            java.util.Base64.getDecoder().decode(vector.compactIntroduction),
            PairingIntroductionCodec.encodeIntroduction(f.introduction),
        )
        val name = PairingIntroductionCodec.compactName("☎😀".repeat(100))
        assertTrue(name.toByteArray(Charsets.UTF_8).size <= 64)
        val intro =
            PairingIntroduction.create(
                f.invitation,
                f.introduction.deviceId,
                name,
                f.introduction.port,
                f.introduction.fingerprint,
            )
        assertTrue(PairingIntroductionCodec.encodeIntroduction(intro).size + 7 <= 255)
        assertTrue(intro.verify(f.invitation))
    }
}
