package com.gafeso.gafeso_mobile

import android.os.Bundle
import android.view.WindowManager
import com.gafeso.reader.DeviceIdentity
import com.gafeso.reader.DeviceKeystore
import com.gafeso.reader.PdfReaderFactory
import com.gafeso.reader.SecureStore
import com.gafeso.reader.SeedProvisioner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hôte Flutter. `FLAG_SECURE` sur la fenêtre (obligatoire : bloque screenshot/screenrecord ET
 * blanchit la vignette recents — fuite démontrée sans lui sur device réel au Spike-B).
 * Enregistre la PlatformView du lecteur natif et le canal de provisioning seed (Étape 1).
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry
            .registerViewFactory("gafeso-pdf-reader", PdfReaderFactory())

        // Canal de provisioning SEED (démo hors-réseau, Étape 1) : exposé UNIQUEMENT en debug.
        // En release il n'est pas enregistré et les assets de démo ne sont pas empaquetés
        // (audit M1) — aucune CEK ni licence auto-signée ne part en production.
        if (BuildConfig.DEBUG) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gafeso/seed")
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "seedParams" -> try {
                            result.success(SeedProvisioner.buildParams(this))
                        } catch (e: Exception) {
                            result.error("SEED", e.message, null)
                        }
                        else -> result.notImplemented()
                    }
                }
        }

        // Canal « appareil » (Étape 2) : expose la clé PUBLIQUE EC pour l'enregistrement et
        // mémorise l'identifiant attribué par le serveur (celui que la licence lie et qui sert
        // d'AAD au déballage EC-KEM). La clé privée ne sort JAMAIS du keystore.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gafeso/device")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "publicKey" -> {
                            DeviceKeystore.ensureKey()
                            result.success(DeviceKeystore.publicKeySpkiB64())
                        }
                        "deviceId" -> result.success(DeviceIdentity.current(this))
                        // Répertoire privé de l'app (évite la dépendance path_provider, qui
                        // imposait en plus un NDK plus récent que celui du projet).
                        "appDir" -> result.success(filesDir.absolutePath)

                        // Luminosité de l'écran, pour la carte de lecteur.
                        //
                        // Fait ICI plutôt qu'avec un greffon : le canal natif existe
                        // déjà, et une dépendance de plus pour dix lignes de Kotlin
                        // irait contre le positionnement du produit — chaque paquet
                        // ajouté est du code tiers dans une application qui chiffre
                        // des documents.
                        //
                        // La valeur porte sur la FENÊTRE, pas sur le réglage système :
                        // elle est rendue à sa valeur d'origine en quittant l'écran, et
                        // ne survit pas à l'application. On ne modifie jamais un réglage
                        // de l'appareil à l'insu de son porteur.
                        "setBrightness" -> {
                            val v = (call.arguments as? Map<*, *>)?.get("value") as? Double
                            runOnUiThread {
                                window.attributes = window.attributes.apply {
                                    screenBrightness =
                                        v?.toFloat() ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                                }
                            }
                            result.success(null)
                        }
                        "isRegistered" -> result.success(DeviceIdentity.isRegistered(this))
                        "storeDeviceId" -> {
                            val id = call.argument<String>("deviceId")
                                ?: return@setMethodCallHandler result.error(
                                    "ARG", "deviceId manquant", null,
                                )
                            DeviceIdentity.store(this, id)
                            result.success(true)
                        }
                        "clearDeviceId" -> { DeviceIdentity.clear(this); result.success(true) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("DEVICE", e.message, null)
                }
            }

        // Coffre local chiffré (clé AES du keystore) : session offline (userId/tenant/nom
        // d'affichage pour le filigrane, jeton). Dart ne manipule que des chaînes déjà
        // déchiffrées par le natif ; rien n'est écrit en clair.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.gafeso/secure")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "put" -> {
                            val name = call.argument<String>("name")!!
                            val value = call.argument<String>("value")!!
                            SecureStore.put(this, name, value)
                            result.success(true)
                        }
                        "get" -> result.success(SecureStore.get(this, call.argument<String>("name")!!))
                        "remove" -> {
                            SecureStore.remove(this, call.argument<String>("name")!!)
                            result.success(true)
                        }
                        "clear" -> { SecureStore.clear(this); result.success(true) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("SECURE", e.message, null)
                }
            }
    }
}
