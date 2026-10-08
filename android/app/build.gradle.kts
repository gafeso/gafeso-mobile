import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.NamedParameterSpec
import java.time.Instant
import java.util.Base64
import java.util.Properties
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * Génère AU BUILD **toute** la fixture de démo hors-réseau (mode seed).
 *
 * Le dépôt ne contient que la SOURCE en clair (`seed-source/seed_demo.pdf`, document
 * synthétique sans donnée réelle, hors `assets/` donc non empaqueté tel quel). À chaque
 * compilation, la tâche produit dans `assets/seed/` :
 *   - une **CEK AES-256 fraîche** (`seed_cek.hex`) et le **blob chiffré** correspondant
 *     (`seed.gafs`, format AEAD segmenté 16 Ko « GAFS1 », identique au backend) ;
 *   - une **paire Ed25519 éphémère**, dont seule la PUBLIQUE est écrite, avec le corps de
 *     licence canonique et sa signature.
 *
 * Aucune clé — ni CEK, ni clé privée de signature — n'est donc versionnée : publier ce dépôt
 * n'expose aucun secret, et deux compilations ne partagent aucune clé.
 *
 * Le corps est sérialisé sous forme CANONIQUE (clés triées) : exactement les octets que
 * `LicenseCanonical.canonicalize` reconstruit côté app, donc la signature vérifie.
 *
 * La licence de seed est liée à un `deviceId` SYNTHÉTIQUE fixe : hors réseau, aucun serveur
 * n'attribue d'identifiant, et `SeedProvisioner` fait porter cette valeur à l'appareil (comme
 * le ferait un enregistrement). Validité longue : c'est une fixture de développement.
 */
val seedDeviceId = "seed-device-0001"
// Les assets de démo (blob chiffré, CEK, licence auto-signée) vivent dans le source set
// **debug** : ils ne sont donc PAS empaquetés dans le release (audit M1). Le canal natif
// `com.gafeso/seed` est lui aussi conditionné à `BuildConfig.DEBUG` (voir MainActivity).
val seedAssetsDir = layout.projectDirectory.dir("src/debug/assets/seed")
val seedSourcePdf = layout.projectDirectory.file("seed-source/seed_demo.pdf")

/**
 * Chiffre en blob **AEAD segmenté** au format du backend :
 *   MAGIC("GAFS1\u0000") | u32LE headerLen | headerJSON{file_len,seg_size,n_segs}
 *   | N × [ nonce(12) | ciphertext | tag(16) ]
 * AAD de chaque segment = (index, seg_size, file_len) en trois u64 little-endian, AES-256-GCM.
 * Miroir exact de `content-crypto.ts` et de `SegmentedBlobReader`.
 */
fun encryptSegmented(plain: ByteArray, cek: ByteArray, segSize: Int = 16 * 1024): ByteArray {
    val fileLen = plain.size
    val nSegs = (fileLen + segSize - 1) / segSize
    val header = ("{\"file_len\":" + fileLen + ",\"seg_size\":" + segSize +
        ",\"n_segs\":" + nSegs + "}").toByteArray(Charsets.UTF_8)
    val out = ByteArrayOutputStream()
    out.write(byteArrayOf(0x47, 0x41, 0x46, 0x53, 0x31, 0x00)) // "GAFS1\u0000"
    out.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(header.size).array())
    out.write(header)
    val rnd = SecureRandom()
    val key = SecretKeySpec(cek, "AES")
    for (k in 0 until nSegs) {
        val from = k * segSize
        val chunk = plain.copyOfRange(from, minOf(from + segSize, fileLen))
        val nonce = ByteArray(12).also { rnd.nextBytes(it) }
        val aad = ByteBuffer.allocate(24).order(ByteOrder.LITTLE_ENDIAN)
            .putLong(k.toLong()).putLong(segSize.toLong()).putLong(fileLen.toLong()).array()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad)
        out.write(nonce)
        out.write(cipher.doFinal(chunk)) // ciphertext + tag
    }
    return out.toByteArray()
}

val generateSeedLicense by tasks.registering {
    description = "Génère la licence de seed signée (clé privée jamais écrite sur disque)."
    // Entrée : les métadonnées du document de seed ; sorties : publique + corps + signature.
    inputs.file(seedAssetsDir.file("seed_meta.json"))
    inputs.file(seedSourcePdf)
    outputs.files(
        seedAssetsDir.file("seed_ed25519_pub.pem"),
        seedAssetsDir.file("seed_license_body.json"),
        seedAssetsDir.file("seed_license_sig.b64"),
        seedAssetsDir.file("seed_cek.hex"),
        seedAssetsDir.file("seed.gafs"),
    )

    doLast {
        seedAssetsDir.asFile.mkdirs()

        // ── 1) CEK fraîche + blob chiffré (AEAD segmenté 16 Ko, format GAFS1) ────────
        val cek = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val clear = seedSourcePdf.asFile.readBytes()
        seedAssetsDir.file("seed.gafs").asFile.writeBytes(encryptSegmented(clear, cek))
        seedAssetsDir.file("seed_cek.hex").asFile
            .writeText(cek.joinToString("") { "%02x".format(it) })
        logger.lifecycle(
            "Blob de démo chiffré : ${clear.size} o de clair → " +
                "${seedAssetsDir.file("seed.gafs").asFile.length()} o (CEK générée au build).",
        )

        // ── 2) Licence signée ───────────────────────────────────────────────────────
        val metaText = seedAssetsDir.file("seed_meta.json").asFile.readText()
        fun metaField(name: String): String =
            Regex("\"$name\"\\s*:\\s*\"([^\"]*)\"").find(metaText)?.groupValues?.get(1)
                ?: error("champ $name absent de seed_meta.json")

        val issuedAt = Instant.now()
        val expiresAt = issuedAt.plusSeconds(3650L * 86400) // fixture de dev : validité longue

        // Corps CANONIQUE : clés triées récursivement, comme license-crypto.ts.
        val body = buildString {
            append("{")
            append("\"deviceId\":\"").append(seedDeviceId).append("\",")
            append("\"docId\":\"").append(metaField("docId")).append("\",")
            append("\"expiresAt\":\"").append(expiresAt.toString()).append("\",")
            append("\"issuedAt\":\"").append(issuedAt.toString()).append("\",")
            append("\"rights\":{\"noPrint\":true,\"watermark\":true},")
            append("\"tenant\":\"").append(metaField("tenant")).append("\",")
            append("\"userId\":\"").append(metaField("userId")).append("\",")
            append("\"v\":1")
            append("}")
        }

        val pair = KeyPairGenerator.getInstance("Ed25519").apply {
            initialize(NamedParameterSpec.ED25519)
        }.generateKeyPair()

        val signature = Signature.getInstance("Ed25519").run {
            initSign(pair.private)
            update(body.toByteArray(Charsets.UTF_8))
            sign()
        }

        val pubB64 = Base64.getEncoder().encodeToString(pair.public.encoded)
        seedAssetsDir.file("seed_ed25519_pub.pem").asFile.writeText(
            "-----BEGIN PUBLIC KEY-----\n" +
                pubB64.chunked(64).joinToString("\n") + "\n-----END PUBLIC KEY-----\n",
        )
        seedAssetsDir.file("seed_license_body.json").asFile.writeText(body)
        seedAssetsDir.file("seed_license_sig.b64").asFile.writeText(
            Base64.getEncoder().encodeToString(signature),
        )
        // pair.private sort de portée ici : rien n'est persisté.
        logger.lifecycle("Licence de seed générée (clé privée non persistée).")
    }
}

// Les assets de seed sont générés dans le source set debug : on ne les régénère donc que pour
// les variants DEBUG (mergeDebugAssets). Le release ne dépend pas de cette tâche et n'embarque
// aucun asset de démo.
tasks.matching { it.name.matches(Regex("merge.*Debug.*Assets")) }
    .configureEach { dependsOn(generateSeedLicense) }

// Signature de release : lue depuis android/key.properties (hors dépôt, gitignoré). Voir le
// README (« Signature de release »).
//
// Sans ce fichier, un build de release ÉCHOUE (voir le garde-fou plus bas) : un repli
// silencieux sur la clé de debug produirait un APK d'apparence normale mais signé avec une clé
// publique et universelle — donc forgeable par n'importe qui. L'échappatoire explicite
// `-PallowDebugSigning=true` permet à un contributeur de compiler un checkout neuf en le
// SACHANT ; l'artefact obtenu n'est alors pas publiable.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseKeystore = keystorePropertiesFile.exists()
val allowDebugSigning = (project.findProperty("allowDebugSigning") as String?) == "true"

/**
 * Refuse de produire un artefact de release signé avec la clé de debug.
 *
 * Le contrôle est fait sur le GRAPHE DE TÂCHES, pas à la configuration : lever l'erreur à la
 * configuration ferait échouer TOUS les builds (debug inclus), alors que seule la production
 * d'un artefact de release est concernée.
 */
gradle.taskGraph.whenReady {
    val buildsReleaseArtifact = allTasks.any { t ->
        t.name.contains("Release") &&
            (t.name.startsWith("assemble") || t.name.startsWith("bundle") || t.name.startsWith("package"))
    }
    if (buildsReleaseArtifact && !hasReleaseKeystore && !allowDebugSigning) {
        throw GradleException(
            """
            Keystore de release absent : android/key.properties est introuvable.

            Un artefact de release NE DOIT PAS être signé avec la clé de debug Android : elle est
            publique et universelle, donc n'importe qui pourrait forger un APK se faisant passer
            pour le vôtre.

            → Pour produire un artefact publiable : créez android/key.properties (voir la section
              « Signature de release » du README).
            → Pour compiler malgré tout un checkout neuf, en connaissance de cause :
              flutter build apk --release -PallowDebugSigning=true
              L'APK obtenu est signé avec la clé de debug : ne le distribuez pas.
            """.trimIndent(),
        )
    }
}

android {
    // EXCLUSION EXPLICITE DE L'ARM 32 BITS.
    //
    // `ndk.abiFilters` ne filtre QUE la compilation native locale (CMake). Le
    // moteur Flutter et les AAR tiers (caméra, ML Kit) sont empaquetés par un
    // autre chemin : constaté sur l'APK de release, `lib/armeabi-v7a/` y
    // contenait libflutter.so et libapp.so alors que libpdfium.so n'existe QUE
    // pour arm64-v8a et x86_64.
    //
    // Conséquence sur un téléphone 32 bits — courant et bon marché, donc
    // exactement notre marché : l'application S'INSTALLE, la connexion marche,
    // l'étagère marche, et le LECTEUR échoue à l'ouverture du premier
    // document. Le cœur du produit, en panne au pire moment, sans que rien ne
    // l'ait annoncé.
    //
    // Mieux vaut ne PAS être installable que d'être installable et cassé : les
    // magasins d'applications filtrent par ABI, l'appareil ne se voit tout
    // simplement pas proposer l'application. Le jour où l'on fournira une
    // libpdfium 32 bits, il suffira de retirer cette exclusion.
    packaging {
        jniLibs {
            excludes += listOf("lib/armeabi-v7a/**")
        }
    }

    namespace = "com.gafeso.gafeso_mobile"
    compileSdk = flutter.compileSdkVersion
    // ⚠ ALIGNÉ SUR CE QUE LES PLUGINS RÉCLAMENT (flutter_local_notifications et
    // mobile_scanner demandent tous deux le 28.2). Le projet imposait le 26.3 :
    // du code natif tiers se construisait donc avec un NDK que ses auteurs
    // n'avaient pas visé — ça marche jusqu'au jour où ça casse, et ça casse
    // alors dans du natif, là où le diagnostic coûte le plus cher.
    // ⚠ ALIGNÉ SUR CE QUE LES PLUGINS RÉCLAMENT : flutter_local_notifications et
    // mobile_scanner demandent tous deux le 28.2. Le projet imposait le 26.3 — du
    // code natif tiers se construisait donc avec un NDK que ses auteurs n.avaient
    // pas visé. Ça marche jusqu.au jour où ça casse, et ça casse alors dans du
    // natif, là où le diagnostic coûte le plus cher.
    ndkVersion = "28.2.13676358"

    // Expose BuildConfig.DEBUG au code Kotlin (utilisé pour n'exposer le canal seed qu'en debug).
    buildFeatures { buildConfig = true }

    // ⚠ Drapeau de CAPTURE D'ÉCRAN, pour produire les visuels de la fiche Play.
    // `FLAG_SECURE` interdit la capture à tout le monde, nous compris. Ce drapeau
    // la lève — et il vaut `false` partout sauf si on le demande explicitement :
    //   flutter build apk --debug --dart-define=GAFESO_CAPTURES_FICHE=true
    defaultConfig {
        val capturesDemandees = (project.findProperty("captures") as String? ?: "false").toBoolean()
        buildConfigField("boolean", "CAPTURES_FICHE", capturesDemandees.toString())

        // ⚠ UN BUILD QUI AFFAIBLIT UNE PROTECTION DOIT LE DIRE, DANS SON NOM.
        //
        // Les deux variantes portaient le MÊME `versionName` : rien, ni dans
        // l'app ni dans `dumpsys`, ne permettait de savoir laquelle était
        // installée. Un téléphone laissait donc passer les captures sans qu'on
        // puisse dire si c'était un défaut du blocage ou la variante prévue
        // pour cela — et c'est exactement la question qui s'est posée.
        //
        // Le suffixe est porté par le versionName, donc visible partout :
        // à l'écran « À propos », dans les réglages Android, dans `dumpsys`.
        if (capturesDemandees) {
            versionNameSuffix = "+CAPTURES-NON-DISTRIBUABLE"
        }
    }

    compileOptions {
        // Exigé par flutter_local_notifications : le greffon utilise l'API
        // java.time, absente des Android anciens. Le « desugaring » la fournit
        // à la compilation plutôt que d'imposer un minSdk plus haut — ce qui
        // aurait exclu les appareils les plus modestes, c'est-à-dire notre
        // public.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gafeso.gafeso_mobile"
        minSdk = 33 // plancher Android 13 Go : garantit Ed25519 natif + keystore RSA-OAEP
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // arm64 = device réel (TECNO) ; x86_64 = émulateur. Pas d'armeabi-v7a (pas de .so 32-bit).
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild { cmake { cppFlags += "-std=c++17"; abiFilters += listOf("arm64-v8a", "x86_64") } }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        // Clé de RELEASE : jamais dans le dépôt. Chemin + mots de passe fournis par
        // android/key.properties (gitignoré). v1+v2+v3 activés (intégrité APK Signature Scheme).
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // Clé de RELEASE dès que key.properties est présent. Sinon la clé de debug, mais le
            // garde-fou `gradle.taskGraph.whenReady` ci-dessus aura déjà fait échouer le build —
            // sauf `-PallowDebugSigning=true`, où le contributeur assume un APK non distribuable.
            signingConfig =
                if (hasReleaseKeystore) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
            // ⚠ Indispensable : R8 supprimait `SegmentedBlobReader.readRange`, appelée
            // uniquement depuis le JNI (callback PDFium) — le lecteur refusait d'ouvrir le
            // document en release alors que le debug fonctionnait. Voir proguard-rules.pro.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Lecteur natif : pagination + recyclage des vues (fenêtre glissante bitmaps).
    implementation("androidx.viewpager2:viewpager2:1.1.0")
    implementation("androidx.recyclerview:recyclerview:1.3.2")

    // Vérification Ed25519 des licences, INDÉPENDANTE des fournisseurs de la ROM.
    // Constaté sur device (HONOR/Android 16) : les seuls services Ed25519 exposés viennent
    // d'AndroidKeyStore, qui refuse d'importer une clé publique externe — aucun fournisseur
    // généraliste ne propose KeyFactory.Ed25519. Tink embarque la primitive (brique éprouvée,
    // conforme à la règle « ne pas réinventer de crypto »).
    implementation("com.google.crypto.tink:tink-android:1.13.0")
}
