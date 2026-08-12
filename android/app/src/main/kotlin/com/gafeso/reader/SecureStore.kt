package com.gafeso.reader

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Coffre local pour la **session offline** (userId / tenant / nom d'affichage servant au
 * filigrane, jeton). Chiffré par une clé **AES-256-GCM non-exportable de l'Android Keystore** :
 * les données ne sont lisibles que sur cet appareil, par cette app. Le blob chiffré est rangé
 * dans les SharedPreferences (nonce préfixé), jamais en clair.
 *
 * Aucune dépendance externe — même parti pris que le reste de la crypto de l'app.
 */
object SecureStore {
    private const val ALIAS = "gafeso_session_key"
    private const val KS = "AndroidKeyStore"
    private const val PREFS = "gafeso_secure"
    private const val NONCE_LEN = 12
    private const val TAG_BITS = 128

    private fun ks(): KeyStore = KeyStore.getInstance(KS).apply { load(null) }

    private fun key(): SecretKey {
        val existing = ks().getKey(ALIAS, null) as? SecretKey
        if (existing != null) return existing
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KS)
        gen.init(
            KeyGenParameterSpec.Builder(
                ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return gen.generateKey()
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Chiffre et stocke une valeur (chaîne). */
    fun put(ctx: Context, name: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ct = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val packed = cipher.iv + ct // nonce (12 o) || ciphertext+tag
        prefs(ctx).edit().putString(name, Base64.getEncoder().encodeToString(packed)).apply()
    }

    /** Relit et déchiffre une valeur, ou null si absente/illisible (clé changée, données altérées). */
    fun get(ctx: Context, name: String): String? {
        val packedB64 = prefs(ctx).getString(name, null) ?: return null
        return try {
            val packed = Base64.getDecoder().decode(packedB64)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                key(),
                GCMParameterSpec(TAG_BITS, packed.copyOfRange(0, NONCE_LEN)),
            )
            String(cipher.doFinal(packed.copyOfRange(NONCE_LEN, packed.size)), Charsets.UTF_8)
        } catch (_: Exception) {
            // Données inexploitables : on les purge plutôt que de laisser un état douteux.
            remove(ctx, name)
            null
        }
    }

    fun remove(ctx: Context, name: String) {
        prefs(ctx).edit().remove(name).apply()
    }

    /** Purge totale (déconnexion). */
    fun clear(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }
}
