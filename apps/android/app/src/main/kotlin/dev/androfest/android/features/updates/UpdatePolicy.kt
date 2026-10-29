package dev.androfest.android.features.updates

import java.net.URI
import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable data class UpdateAsset(val url: String, val sha256: String, val size: Long)

@Serializable
data class UpdateManifest(val version: String, val build: Long, val android: UpdateAsset)

/** Only release metadata signed by our offline Ed25519 identity can authorize a download. */
object UpdatePolicy {
    fun verify(bytes: ByteArray, signature: String, publicKey: String): UpdateManifest {
        require(bytes.size in 1..65_536) { "Invalid update metadata size." }
        val raw = Base64.getDecoder().decode(publicKey)
        require(raw.size == 32)
        val prefix =
            byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00)
        val key = KeyFactory.getInstance("Ed25519").generatePublic(X509EncodedKeySpec(prefix + raw))
        val verifier = Signature.getInstance("Ed25519")
        verifier.initVerify(key)
        verifier.update("Twinvia Android Update v1\u0000".toByteArray(Charsets.UTF_8))
        verifier.update(bytes)
        require(verifier.verify(Base64.getDecoder().decode(signature.trim()))) {
            "Update signature is invalid."
        }
        val manifest =
            Json { ignoreUnknownKeys = true }
                .decodeFromString<UpdateManifest>(bytes.decodeToString())
        require(manifest.version.matches(Regex("[0-9]+\\.[0-9]+\\.[0-9]+")) && manifest.build > 0)
        val asset = manifest.android
        val uri = URI(asset.url)
        require(
            uri.scheme == "https" &&
                uri.host == "github.com" &&
                uri.rawQuery == null &&
                uri.rawFragment == null &&
                uri.userInfo == null &&
                uri.port == -1
        )
        require(
            uri.path.startsWith("/maliyilmaz0/twinvia/releases/download/v${manifest.version}/") &&
                uri.path.endsWith(".apk")
        )
        require(!uri.path.contains("..") && !uri.path.contains('%'))
        require(asset.sha256.matches(Regex("[a-f0-9]{64}")) && asset.size in 1..209_715_200)
        return manifest
    }
}
