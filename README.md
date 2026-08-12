<p align="center">
  <img src="assets/marque/gafeso_horizontal.png" alt="Gafeso" width="300">
</p>

# Gafeso Mobile

Lecteur mobile **hors-ligne** pour [Gafeso](https://gafeso.org), le SIGB open-source
multi-établissements. Application Android permettant aux lecteurs de consulter, hors
connexion, les documents numériques auxquels leur établissement leur donne accès.

> **Statut : en développement actif (MVP Android).** Le cœur de sécurité offline est
> implémenté et prouvé sur appareil réel ; l'app n'est pas encore publiée sur le Play Store.

## Ce que c'est

L'app se branche sur l'API d'une instance Gafeso existante (elle ne réécrit aucun backend).
Elle télécharge les documents autorisés du lecteur et les rend consultables **sans réseau**,
tout en respectant le contrôle d'accès de l'établissement (classe, abonnement, expiration).

## Sécurité — le modèle en bref

La lecture offline de contenu sous droits repose sur une protection « maison » proportionnée
(objectif : bloquer le partage courant, pas prétendre à l'inviolabilité) :

- **Contenu chiffré au repos** : blobs AES-256-GCM segmentés ; jamais de clair écrit sur le
  disque, déchiffrement à la volée en mémoire au rendu.
- **Lecteur exclusif** : rendu natif via PDFium ; aucun lecteur tiers ne peut ouvrir le
  contenu.
- **Clé liée à l'appareil** : clé EC P-256 non-exportable dans l'Android Keystore ; la clé de
  contenu est enveloppée par un KEM (ECDH + HKDF-SHA256 + AES-GCM) — pas de SHA-1.
- **Licence bornée dans le temps** : signée Ed25519, vérifiable hors-ligne, liée à
  l'utilisateur, à l'appareil et à l'établissement ; révocable au retour en ligne.
- **Protections d'écran** : `FLAG_SECURE` (capture bloquée, vignette recents masquée),
  filigrane incrusté, garde anti-recul d'horloge.

Ce résumé ne suffit pas à instruire un déploiement. Le **modèle de sécurité de la lecture
hors-ligne** est décrit en entier — modèle de menace, primitives, bornage temporel, révocation
et **limites assumées** — dans la note d'architecture du dépôt principal :
[docs/architecture-securite-offline.md](https://github.com/gafeso/gafeso/blob/main/docs/architecture-securite-offline.md).
C'est la pièce à lire avant de déployer, en particulier sa section « Limites assumées » : aucune
protection côté client n'est inviolable sur un appareil dont le porteur a le contrôle total.

## Prérequis

- Une instance **Gafeso** accessible (API `offline-licensing`).
- Flutter, Android SDK + NDK. **minSdk 33** (Android 13) — requis pour les opérations
  keystore utilisées.

## Développement

```bash
flutter pub get
flutter run           # sur un appareil/emulateur Android
flutter build apk     # build debug
```

Le lecteur natif (Kotlin/NDK + PDFium) vit sous `android/`. Les tests d'intégration gatés
(`MOBILE_E2E=1`) s'exécutent contre une instance backend de test.

Le **mode démo hors-réseau** (assets `seed/`, canal `com.gafeso/seed`) n'existe **qu'en build
debug** : il n'est jamais empaqueté ni exposé en release.

## Build de production (release)

Le trafic en clair est interdit en release : fournissez une URL **HTTPS**.

```bash
flutter build apk --release \
  --dart-define=GAFESO_API_URL=https://api.votre-ecole.exemple
```

### Signature de release

L'APK de release est signé avec une clé **hors dépôt** — jamais la clé de debug, jamais de clé
ni de mot de passe committés (`*.jks`, `key.properties` sont gitignorés).

1. Générer un keystore (une fois), **en dehors de l'arborescence du dépôt** :

   ```bash
   keytool -genkeypair -v -keystore ~/.gafeso-keystore/gafeso-release.jks \
     -alias gafeso -keyalg RSA -keysize 4096 -validity 10000
   ```

2. Créer `android/key.properties` (gitignoré) pointant vers ce keystore :

   ```properties
   storeFile=/chemin/absolu/vers/gafeso-release.jks
   storePassword=…
   keyAlias=gafeso
   keyPassword=…
   ```

3. `flutter build apk --release` signe alors en **v1+v2+v3**.

**Sans `key.properties`, un build de release échoue volontairement** :

```
Keystore de release absent : android/key.properties est introuvable.
```

C'est délibéré : un repli silencieux sur la clé de debug produirait un APK d'apparence normale
mais signé avec une clé **publique et universelle**, que n'importe qui peut donc forger.

Sur un checkout neuf (contributeur, CI sans secret), on peut compiler malgré tout en l'assumant
explicitement :

```bash
flutter build apk --release -PallowDebugSigning=true
```

L'APK produit est alors signé avec la clé de debug (`CN=Android Debug`) : il sert à tester la
compilation, **il ne doit jamais être distribué**. Les builds `--debug` ne sont pas concernés.

> ⚠️ Sauvegardez le keystore et ses mots de passe hors ligne : les perdre empêche toute mise à
> jour de l'app (Android exige la même clé de signature). Ne les committez jamais.

## Licence

Distribué sous **GNU Affero General Public License v3.0** (AGPL-3.0). Voir [`LICENSE`](LICENSE).

## Contribuer

Les contributions sont bienvenues — voir [`CONTRIBUTING.md`](CONTRIBUTING.md). Pour signaler
une faille de sécurité, voir [`SECURITY.md`](SECURITY.md).

---

Édité par **ResurgiTech** dans le cadre du projet open-source **Gafeso**.
