package dev.androfest.android.core.connection

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import dev.twinvia.protocol.PairingInvitation
import dev.twinvia.protocol.WireCodec
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.serialization.encodeToString

class SecurePeerStore(context: Context) {
    private val preferences = context.getSharedPreferences("bridge-peer", Context.MODE_PRIVATE)
    private val alias = "androfest.peer.storage.v1"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(alias)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                .apply {
                    init(
                        KeyGenParameterSpec.Builder(
                                alias,
                                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                            )
                            .setKeySize(256)
                            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                            .build()
                    )
                }
                .generateKey()
        }
        return store.getKey(alias, null) as SecretKey
    }

    fun load(): PairingInvitation? {
        val encoded = preferences.getString("encrypted", null) ?: return null
        return runCatching {
                val bytes = Base64.decode(encoded, Base64.NO_WRAP)
                require(bytes.size > 28)
                val cipher =
                    Cipher.getInstance("AES/GCM/NoPadding").apply {
                        init(
                            Cipher.DECRYPT_MODE,
                            key(),
                            GCMParameterSpec(128, bytes.copyOfRange(0, 12)),
                        )
                    }
                WireCodec.json
                    .decodeFromString<PairingInvitation>(
                        cipher.doFinal(bytes.copyOfRange(12, bytes.size)).toString(Charsets.UTF_8)
                    )
                    .also { it.validate(allowExpired = true) }
            }
            .getOrNull()
    }

    fun save(invitation: PairingInvitation) {
        val cipher =
            Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        require(cipher.iv.size == 12)
        val encrypted =
            cipher.iv +
                cipher.doFinal(
                    WireCodec.json.encodeToString(invitation).toByteArray(Charsets.UTF_8)
                )
        check(
            preferences
                .edit()
                .putString("encrypted", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .commit()
        )
    }

    fun clear() {
        check(preferences.edit().clear().commit())
    }
}
