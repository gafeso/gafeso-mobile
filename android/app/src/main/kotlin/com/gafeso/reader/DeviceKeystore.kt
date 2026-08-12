package com.gafeso.reader

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

/**
 * Clé d'appareil = paire **EC P-256 (secp256r1) non-exportable** dans l'Android Keystore
 * (`PURPOSE_AGREE_KEY`, hardware-backed si dispo). La clé privée ne quitte jamais le keystore ;
 * elle sert uniquement à l'accord de clé ECDH qui permet de DÉBALLER la CEK enveloppée par le
 * backend. Un blob copié sur un autre appareil est illisible (sa CEK est enveloppée pour CE
 * keystore).
 *
 * **EC-KEM (amendement crypto 2026-07-29) — aucun SHA-1 nulle part.** Remplace RSA-OAEP, dont
 * le MGF1 est verrouillé sur SHA-1 par le keystore du plancher (API 33 ; `setMgf1Digests` =
 * API 34). Déballage :
 *   1. `Z = ECDH(device_priv (keystore), epk)` ;
 *   2. `KEK = HKDF-SHA256(ikm=Z, salt="", info="gafeso/cek-wrap/v1", L=32)` ;
 *   3. `CEK = AES-256-GCM-decrypt(KEK, nonce, ct)` avec **AAD = deviceId**.
 * Les paramètres HKDF sont identiques au bit près à ceux du backend (`license-crypto.ts`).
 */
object DeviceKeystore {
    private const val ALIAS = "gafeso_device_key_ec"
    private const val KS = "AndroidKeyStore"
    private const val CURVE = "secp256r1" // P-256
    private const val HKDF_INFO = "gafeso/cek-wrap/v1"
    private const val KEK_LEN = 32
    private const val WRAP_VERSION = 1

    private fun ks(): KeyStore = KeyStore.getInstance(KS).apply { load(null) }

    /** Crée la paire EC au 1er appel, la réutilise ensuite. Idempotent. */
    fun ensureKey() {
        if (ks().containsAlias(ALIAS)) return
        val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KS)
        gen.initialize(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_AGREE_KEY)
                .setAlgorithmParameterSpec(ECGenParameterSpec(CURVE))
                .build(),
        )
        gen.generateKeyPair()
    }

    private fun publicKey(): PublicKey {
        ensureKey()
        return ks().getCertificate(ALIAS).publicKey
    }

    private fun privateKey(): PrivateKey {
        ensureKey()
        return ks().getKey(ALIAS, null) as PrivateKey
    }

    /**
     * Clé publique en **SPKI DER base64** — le format attendu par `POST /offline/devices`
     * (le backend la relit avec `createPublicKey({format:'der', type:'spki'})`).
     */
    fun publicKeySpkiB64(): String = Base64.getEncoder().encodeToString(publicKey().encoded)

    /**
     * Empreinte locale de la clé publique — sert d'identifiant de repli (mode seed, hors
     * réseau). En production, l'identifiant qui compte est celui **attribué par le serveur**
     * (voir DeviceIdentity) car c'est lui que le backend met dans la licence et en AAD.
     */
    fun publicKeyFingerprint(): String {
        val h = MessageDigest.getInstance("SHA-256").digest(publicKey().encoded)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(h).take(22)
    }

    /**
     * Déballe la CEK d'une enveloppe EC-KEM `{v, epk, nonce, ct}` (JSON du backend).
     * `deviceId` = identifiant lié par le serveur, utilisé en AAD : une enveloppe destinée à
     * un autre appareil échoue à l'authentification GCM.
     */
    fun unwrapCek(wrappedJson: String, deviceId: String): ByteArray {
        val w = JSONObject(wrappedJson)
        val v = w.getInt("v")
        require(v == WRAP_VERSION) { "version d'enveloppe de CEK non supportée : $v" }

        val epk = KeyFactory.getInstance("EC")
            .generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(w.getString("epk"))))
        val z = KeyAgreement.getInstance("ECDH").run {
            init(privateKey()); doPhase(epk, true); generateSecret()
        }
        val kek = hkdfSha256(z, ByteArray(0), HKDF_INFO.toByteArray(Charsets.UTF_8), KEK_LEN)
        z.fill(0)
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(kek, "AES"),
                GCMParameterSpec(128, Base64.getDecoder().decode(w.getString("nonce"))),
            )
            cipher.updateAAD(deviceId.toByteArray(Charsets.UTF_8))
            return cipher.doFinal(Base64.getDecoder().decode(w.getString("ct")))
        } finally {
            kek.fill(0)
        }
    }

    /**
     * SEED UNIQUEMENT : enveloppe une CEK pour CET appareil, en EC-KEM, sans réseau (paire
     * éphémère générée en logiciel, ECDH contre la clé PUBLIQUE du keystore → même Z que
     * l'ECDH keystore côté déballage). En production c'est le serveur qui enveloppe.
     */
    fun wrapCekForSelf(cek: ByteArray, deviceId: String): String {
        val eph = KeyPairGenerator.getInstance("EC").apply {
            initialize(ECGenParameterSpec(CURVE))
        }.generateKeyPair()
        val z = KeyAgreement.getInstance("ECDH").run {
            init(eph.private); doPhase(publicKey(), true); generateSecret()
        }
        val kek = hkdfSha256(z, ByteArray(0), HKDF_INFO.toByteArray(Charsets.UTF_8), KEK_LEN)
        z.fill(0)
        try {
            val nonce = ByteArray(12).also { java.security.SecureRandom().nextBytes(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(kek, "AES"), GCMParameterSpec(128, nonce))
            cipher.updateAAD(deviceId.toByteArray(Charsets.UTF_8))
            val ct = cipher.doFinal(cek)
            return JSONObject().apply {
                put("v", WRAP_VERSION)
                put("epk", Base64.getEncoder().encodeToString(eph.public.encoded))
                put("nonce", Base64.getEncoder().encodeToString(nonce))
                put("ct", Base64.getEncoder().encodeToString(ct))
            }.toString()
        } finally {
            kek.fill(0)
        }
    }

    /** HKDF-SHA256 (RFC 5869) : extract puis expand. Miroir de `hkdfSync` côté backend. */
    private fun hkdfSha256(ikm: ByteArray, salt: ByteArray, info: ByteArray, len: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        // RFC 5869 : un salt vide équivaut à HashLen octets de zéros.
        val realSalt = if (salt.isEmpty()) ByteArray(32) else salt
        mac.init(SecretKeySpec(realSalt, "HmacSHA256"))
        val prk = mac.doFinal(ikm)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        val out = ByteArray(len)
        var t = ByteArray(0)
        var pos = 0
        var counter = 1
        while (pos < len) {
            mac.reset()
            mac.update(t)
            mac.update(info)
            mac.update(counter.toByte())
            t = mac.doFinal()
            val n = minOf(t.size, len - pos)
            System.arraycopy(t, 0, out, pos, n)
            pos += n
            counter++
        }
        return out
    }
}
