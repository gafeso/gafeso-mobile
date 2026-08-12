# Recette d'appareil réel — lot mobile 2

> Tout ce qui suit est couvert par des tests automatisés. Ce qui ne l'est pas,
> c'est **l'enchaînement sur un vrai téléphone** : une permission refusée, une
> caméra qui n'a pas le focus, un réseau qui tombe pour de bon. C'est là qu'on
> verra si le parcours tient bout à bout.

## 0. Contrôle préalable BLOQUANT — architecture de l'appareil

**L'ARM 32 bits n'est plus supporté.** L'APK ne contient plus `armeabi-v7a` :
le moteur Flutter y était packagé alors que `libpdfium.so` n'existe que pour
`arm64-v8a` et `x86_64`. Un téléphone 32 bits installait l'application et le
**lecteur échouait à l'ouverture du premier document** — le cœur du produit,
en panne au pire moment. Mieux vaut ne pas être installable qu'être installable
et cassé.

Conséquence pratique : **un téléphone `armeabi-v7a` ne pourra plus installer
l'APK**, et `adb install` échouera avec `INSTALL_FAILED_NO_MATCHING_ABIS`.
Ce n'est pas une régression à corriger sur place, c'est le comportement voulu.

```bash
./scripts/verifier-appareil.sh
```

Attendu : `arm64-v8a` (ou `x86_64` sur émulateur) et SDK ≥ 33.

## 1. Installation SANS URL compilée

C'est le point de l'étape 1 : un seul binaire pour tous les établissements.

```bash
flutter build apk --release          # PAS de --dart-define=GAFESO_API_URL
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

**À vérifier au premier lancement :** l'application demande l'adresse de la
bibliothèque. Elle ne doit PAS démarrer sur une adresse d'émulateur.

## 2. Scanner le QR d'un établissement

Le QR s'imprime depuis l'écran **Administration → Établissement** du site
(section « QR d'inscription », bouton *Affiche A4*).

**À vérifier :**
- le scan ouvre une confirmation qui **affiche le domaine en clair** ;
- refuser ramène à la saisie, sans rien mémoriser ;
- accepter enchaîne directement sur la connexion, sans redemander l'école.

**Cas à éprouver aussi :** saisir une adresse en `http://` — l'application doit
la refuser en disant pourquoi, pas échouer plus tard.

## 3. Se connecter

Compte étudiant de l'établissement. **À vérifier :** un mot de passe erroné
donne un message lisible, pas une trace d'exception.

## 4. Voir ses prêts

**À vérifier :**
- les jours restants sont en langage courant (« à rendre dans 3 jours ») ;
- un prêt en retard ressort en rouge ;
- **aucun bandeau de fraîcheur** tant que la synchro date de moins de 6 h ;
- « Renouveler » sur un prêt refusé affiche **le motif** du serveur.

**La permission de notification** doit être demandée ICI — au premier prêt
réel — et pas au démarrage. **La refuser ne doit rien casser** : les échéances
restent visibles.

## 5. Chercher un ouvrage

**À vérifier :** taper un mot lettre à lettre ne déclenche **qu'une** requête
(temporisation 400 ms) ; les accents ne sont pas obligatoires ; une recherche
sans résultat dit « aucun résultat », pas « pas de réseau ».

## 6. Ouvrir un document numérique

Depuis la fiche notice, puis l'étagère. **À vérifier :** le téléchargement
aboutit et le document s'ouvre.

## 7. COUPER LE RÉSEAU — le cœur de la recette

Mode avion, franchement.

**À vérifier, dans cet ordre :**

| écran | attendu |
|---|---|
| Étagère | documents toujours listés |
| Lecture | le document **s'ouvre et se lit** |
| Mon espace | prêts toujours affichés, bandeau « Pas de réseau — données de la dernière synchronisation » |
| Ma carte | code-barres affiché, **aucun** bandeau de fraîcheur |
| Recherche | dit que le réseau manque, **jamais** « aucun résultat » |
| Fiche notice | dit que la fiche vient du serveur, renvoie vers l'étagère |

C'est le scénario du comptoir sans wifi. Un écran vide ou une exception brute à
cette étape est un échec de recette, pas un détail d'affichage.

## 8. Afficher sa carte au comptoir

**À vérifier :** la luminosité monte à l'ouverture et **redescend à la
sortie** ; le numéro est lisible en clair sous le code-barres ; et surtout —
**faire scanner le code par la douchette de la bibliothèque**. C'est la seule
preuve qui compte : le code est celui de l'adhérent (`LEC-…`), en Code 128, et
`circulation/checkout` l'accepte (vérifié côté serveur, jamais sur une vraie
douchette).

## 9. Rappels d'échéance

Difficile à éprouver en séance : les rappels tombent à J-3 et le jour même à
9 h. Pour vérifier sans attendre, avancer l'horloge de l'appareil à la veille
d'une échéance, puis observer la notification le lendemain matin.

**À vérifier au minimum :** aucune notification n'arrive **immédiatement** après
la synchronisation — ce serait le signe qu'un rappel au passé a été planifié.

**L'icône de la barre d'état est une SILHOUETTE**, pas une vignette en couleur.
Android ≥ 5 ne retient que le canal alpha d'une petite icône de notification et
la peint en blanc : une image opaque y devient un carré blanc plein. C'était le
cas jusqu'au 2026-08-11 (l'app pointait `@mipmap/ic_launcher`). On doit
reconnaître le toit et le livre, pas un pavé.

## 10. Icône adaptative — seconde forme de masque

**À faire sur un APPAREIL DE TEST, pas sur un téléphone personnel.** L'étape
demande de changer le thème du système, ce qui modifie l'apparence de toutes les
icônes de l'appareil.

Android masque l'icône selon le lanceur — cercle, carré arrondi, goutte, galet.
Une forme qui tient dans une forme peut se faire rogner dans une autre.

Ce qui est **déjà acquis** et n'a pas à être refait :

- la géométrie, par calcul : le cercle englobant minimal de l'artwork (Ø 717,2
  unités, centré en `(420 ; 393,6)`) est inscrit à 61 % de la largeur de la
  couche, donc contenu par **tout** masque possible — un cercle est le masque le
  plus rogneur, toute autre forme le contient. Voir `scripts/generer-icones.mjs` ;
- le rendu hors ligne dans les **quatre** masques (cercle, squircle, carré
  arrondi, goutte) ;
- le rendu **sur appareil réel** en carré arrondi (Honor BVL-AN16, Magic OS,
  2026-08-11), vérifié via `adb shell am start -a
  android.settings.APPLICATION_DETAILS_SETTINGS -d package:com.gafeso.gafeso_mobile` :
  toit blanc net, livre orange, filet central, aucun rognage.

Ce qui **reste** à faire ici : la même vérification sous une **seconde** forme de
masque, à l'écran d'accueil.

- Sur un Pixel ou un AOSP : `adb shell cmd overlay enable com.android.theme.icon.circle`
  (puis `.teardrop`, `.squircle`), et `disable` pour revenir.
- Sur Magic OS / EMUI : ces overlays AOSP **n'existent pas** (`cmd overlay list`
  ne renvoie aucune entrée d'icône). Il faut passer par le gestionnaire de
  thèmes Honor, et rétablir le thème d'origine ensuite.

**À vérifier :** le **toit** reste entier. C'est lui qui est en danger — il
occupe le haut de la marque, là où un masque circulaire rogne le plus. Et c'est
lui qui portait déjà l'autre piège : en `#1B5E3F` sur le fond vert de l'icône, il
disparaissait purement et simplement, d'où son blanc.

---

## Ce qui reste hors de cette recette

- La **révocation** d'une licence pendant que l'appareil est hors réseau : le
  document doit rester lisible jusqu'à la reconnexion, puis être purgé.
- Le comportement sur un appareil **rooté** — hors périmètre, documenté dans la
  note d'architecture de sécurité.
