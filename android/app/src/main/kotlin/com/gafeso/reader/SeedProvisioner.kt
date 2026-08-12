package com.gafeso.reader

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * Provisioning SEED (mode démo hors-réseau, Étape 1). Aucun backend, aucune clé privée.
 *
 * La licence est **générée et signée au BUILD** (tâche Gradle `generateSeedLicense`) : les
 * assets ne contiennent que la clé PUBLIQUE, le corps canonique et la signature. La clé privée
 * de seed n'existe que le temps de la compilation et **n'est ni écrite sur disque ni versionnée**.
 *
 * Assets attendus :
 *   - `seed/seed.gafs`               : blob AEAD segmenté (chiffré par la crypto du backend) ;
 *   - `seed/seed_cek.hex`           : CEK du blob (fixture de test) ;
 *   - `seed/seed_license_body.json` : corps de licence CANONIQUE signé au build ;
 *   - `seed/seed_license_sig.b64`   : signature Ed25519 de ce corps ;
 *   - `seed/seed_ed25519_pub.pem`   : clé publique pour VÉRIFIER ;
 *   - `seed/seed_meta.json`         : { docId, userId, tenant, name }.
 *
 * La licence de seed est liée à un `deviceId` synthétique fixe : hors réseau, aucun serveur ne
 * l'attribue, donc on le fait porter à l'appareil via `DeviceIdentity` — exactement comme le
 * ferait un enregistrement. Le chemin de rendu (vérif → déballage keystore → déchiffrement)
 * est IDENTIQUE à celui de l'Étape 2 ; seule la provenance de la licence change.
 */
object SeedProvisioner {

    /** Doit correspondre à `seedDeviceId` de la tâche Gradle qui signe la licence. */
    private const val SEED_DEVICE_ID = "seed-device-0001"

    fun buildParams(ctx: Context): Map<String, Any?> {
        DeviceKeystore.ensureKey()

        // Hors réseau : l'appareil adopte l'identifiant auquel la licence de seed est liée.
        if (DeviceIdentity.current(ctx) != SEED_DEVICE_ID) {
            DeviceIdentity.store(ctx, SEED_DEVICE_ID)
        }

        // 1) Blob → filesDir (mmap depuis le stockage privé). Un blob poussé (adb push,
        //    ex. gros doc pour mesurer la RAM crête) est PRIORITAIRE sur l'asset.
        val blob = File(ctx.filesDir, "seed.gafs")
        if (!blob.exists()) {
            ctx.assets.open("seed/seed.gafs").use { i -> blob.outputStream().use { i.copyTo(it) } }
        }

        // CEK : filesDir (poussée avec le gros blob) sinon asset. Doit correspondre au blob.
        val cekFile = File(ctx.filesDir, "seed_cek.hex")
        val cekHex =
            if (cekFile.exists()) cekFile.readText().trim() else asset(ctx, "seed/seed_cek.hex").trim()
        val cek = hexToBytes(cekHex)

        // 2) CEK enveloppée pour CET appareil (EC-KEM, AAD = deviceId de la licence).
        val wrappedCek = DeviceKeystore.wrapCekForSelf(cek, SEED_DEVICE_ID)
        java.util.Arrays.fill(cek, 0)

        // 3) Licence pré-signée au build (aucune signature à l'exécution, aucune clé privée).
        val body = asset(ctx, "seed/seed_license_body.json").trim()
        val signature = asset(ctx, "seed/seed_license_sig.b64").trim()
        val publicKeyPem = asset(ctx, "seed/seed_ed25519_pub.pem")

        val meta = JSONObject(asset(ctx, "seed/seed_meta.json"))
        val name = meta.optString("name", "")
        val tenant = meta.getString("tenant")
        val stamp = java.time.Instant.now().toString().take(16).replace('T', ' ')

        return mapOf(
            "blobPath" to blob.absolutePath,
            "licenseBody" to body,
            "signature" to signature,
            "licensePublicKey" to publicKeyPem,
            "wrappedCek" to wrappedCek,
            "userId" to meta.getString("userId"),
            "tenant" to tenant,
            "watermark" to "$name · $tenant · $stamp",
        )
    }

    private fun asset(ctx: Context, path: String): String =
        ctx.assets.open(path).bufferedReader().use { it.readText() }

    private fun hexToBytes(s: String): ByteArray {
        val out = ByteArray(s.length / 2)
        for (i in out.indices) out[i] =
            ((Character.digit(s[i * 2], 16) shl 4) + Character.digit(s[i * 2 + 1], 16)).toByte()
        return out
    }
}
