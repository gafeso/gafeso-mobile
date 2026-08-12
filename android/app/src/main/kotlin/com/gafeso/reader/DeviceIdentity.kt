package com.gafeso.reader

import android.content.Context

/**
 * Identité de l'appareil telle que le BACKEND la connaît. `POST /offline/devices` renvoie un
 * identifiant (UUID) : c'est LUI que le serveur inscrit dans la licence (`deviceId`) et utilise
 * en **AAD** de l'enveloppe EC-KEM. Il doit donc être persisté et réutilisé pour :
 *   - vérifier la liaison `deviceId` de la licence ;
 *   - déballer la CEK (AAD).
 *
 * En mode seed (Étape 1, hors réseau), on retombe sur l'empreinte locale de la clé publique.
 */
object DeviceIdentity {
    private const val PREFS = "gafeso_reader"
    private const val KEY_DEVICE_ID = "server_device_id"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Identifiant serveur s'il existe, sinon l'empreinte locale (seed). */
    fun current(ctx: Context): String =
        prefs(ctx).getString(KEY_DEVICE_ID, null) ?: DeviceKeystore.publicKeyFingerprint()

    /** Vrai si l'appareil est enregistré côté serveur. */
    fun isRegistered(ctx: Context): Boolean = prefs(ctx).contains(KEY_DEVICE_ID)

    /** Mémorise l'identifiant attribué par le backend à l'enregistrement. */
    fun store(ctx: Context, serverDeviceId: String) {
        prefs(ctx).edit().putString(KEY_DEVICE_ID, serverDeviceId).apply()
    }

    /** Purge (désenregistrement / changement de compte). */
    fun clear(ctx: Context) {
        prefs(ctx).edit().remove(KEY_DEVICE_ID).apply()
    }
}
