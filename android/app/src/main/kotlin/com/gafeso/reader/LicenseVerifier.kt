package com.gafeso.reader

import android.content.Context
import org.json.JSONObject
import java.security.GeneralSecurityException
import java.util.Base64

/**
 * Vérifie une licence hors-ligne AVANT tout rendu. Refuse si l'un des points échoue :
 *   - signature **Ed25519** invalide (corps canonique ≠ celui signé par le backend) ;
 *   - licence expirée (`expiresAt` < maintenant) ou pas encore active ;
 *   - liaison rompue : `userId` / `deviceId` / `tenant` ≠ ceux attendus ;
 *   - **recul d'horloge** : l'horloge locale est antérieure à la dernière référence vue
 *     (mémorisée), signe d'une manipulation pour prolonger un bail expiré.
 */
class LicenseVerifier(ctx: Context) {

    companion object {
        /** Version de format de licence acceptée (miroir de LICENSE_VERSION backend). */
        const val LICENSE_VERSION = 1
    }

    private val prefs = ctx.getSharedPreferences("gafeso_reader", Context.MODE_PRIVATE)

    data class Result(val ok: Boolean, val reason: String? = null)

    fun verify(
        bodyJson: String,
        signatureB64: String,
        publicKeyPem: String,
        expectUserId: String,
        expectDeviceId: String,
        expectTenant: String,
    ): Result {
        val body = JSONObject(bodyJson)

        // 0) Version de format (v1 = EC-KEM). Refus net si inconnue : mieux vaut échouer que
        //    d'interpréter une licence d'un schéma cryptographique qu'on ne connaît pas.
        val v = body.optInt("v", -1)
        if (v != LICENSE_VERSION) return Result(false, "version de licence non supportée ($v)")

        // 1) Signature Ed25519 sur le corps CANONIQUE (mêmes octets que le backend).
        val canonical = LicenseCanonical.canonicalize(body).toByteArray(Charsets.UTF_8)
        if (!verifyEd25519(canonical, signatureB64, publicKeyPem)) {
            return Result(false, lastVerifyError?.let { "vérification impossible ($it)" } ?: "signature invalide")
        }

        // 2) Liaisons.
        if (body.optString("userId") != expectUserId) return Result(false, "userId ≠ session")
        if (body.optString("deviceId") != expectDeviceId) return Result(false, "deviceId ≠ appareil")
        if (body.optString("tenant") != expectTenant) return Result(false, "tenant ≠ courant")

        // 3) Anti-recul d'horloge + fenêtre de validité.
        val now = System.currentTimeMillis()
        val lastRef = prefs.getLong("last_ref_ms", 0L)
        if (now < lastRef) return Result(false, "horloge reculée (anti-fraude)")
        val issuedAt = parseIso(body.optString("issuedAt"))
        val expiresAt = parseIso(body.optString("expiresAt"))
        if (expiresAt <= now) return Result(false, "licence expirée")
        if (issuedAt > now + 60_000) return Result(false, "licence pas encore active")

        prefs.edit().putLong("last_ref_ms", maxOf(lastRef, now)).apply()
        return Result(true)
    }

    /** Dernière cause d'échec technique de la vérification (diagnostic ; jamais un secret). */
    var lastVerifyError: String? = null
        private set

    /**
     * Vérifie la signature Ed25519 **sans dépendre des fournisseurs JCA de la ROM**.
     *
     * ⚠ Constaté sur device réel (HONOR/MagicOS, Android 16) : les seuls services Ed25519
     * exposés par la plateforme viennent d'AndroidKeyStore
     * (`AndroidKeyStore/KeyFactory.ED25519`, `AndroidKeyStoreBCWorkaround/Signature.Ed25519`),
     * et AndroidKeyStore **refuse par construction d'importer une clé publique externe**
     * (« To generate a key pair in Android Keystore, use KeyPairGenerator… »). Aucun
     * fournisseur généraliste (Conscrypt) ne propose `KeyFactory.Ed25519`. Vérifier une licence
     * via JCA n'est donc pas portable.
     *
     * On utilise la primitive de **Tink** (brique éprouvée, conforme à la règle « ne pas
     * réinventer de crypto ») : elle prend la clé publique BRUTE de 32 octets, extraite de
     * l'encodage SPKI — dont les 32 derniers octets sont exactement le point public.
     */
    private fun verifyEd25519(message: ByteArray, sigB64: String, pubPem: String): Boolean {
        return try {
            val spki = Base64.getDecoder().decode(
                pubPem.replace("-----BEGIN PUBLIC KEY-----", "")
                    .replace("-----END PUBLIC KEY-----", "").replace(Regex("\\s"), ""),
            )
            require(spki.size >= 32) { "clé publique tronquée (${spki.size} o)" }
            val raw = spki.copyOfRange(spki.size - 32, spki.size)
            com.google.crypto.tink.subtle.Ed25519Verify(raw)
                .verify(Base64.getDecoder().decode(sigB64), message)
            true
        } catch (e: GeneralSecurityException) {
            // Signature réellement invalide : cas métier, pas une panne technique.
            lastVerifyError = null
            false
        } catch (e: Exception) {
            lastVerifyError = "${e.javaClass.simpleName}: ${e.message}"
            android.util.Log.w("GafesoReader", "vérification Ed25519 impossible : $lastVerifyError")
            false
        }
    }

    private fun parseIso(s: String): Long =
        try { java.time.Instant.parse(s).toEpochMilli() } catch (_: Exception) { 0L }
}
