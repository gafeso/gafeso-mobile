# Politique de confidentialité — Gafeso Mobile

**Dernière mise à jour : 22 septembre 2026** · Version de l'application : 1.0.0
**Éditeur : ResurgiTech SARL**, Ouagadougou, Burkina Faso
**Contact : security@gafeso.org**

---

## En une phrase

Gafeso Mobile ne possède aucun serveur. L'application parle **uniquement au
serveur de votre établissement**, dont l'adresse est vous qui la saisissez. Nous,
éditeur de l'application, **ne recevons aucune donnée** : ni compte, ni lecture,
ni statistique.

---

## 1. Qui est responsable de vos données

C'est **votre établissement** (université, bibliothèque) qui héberge Gafeso et
qui est responsable de vos données. L'application n'est qu'un client : elle se
connecte à l'adresse que vous indiquez au premier lancement.

ResurgiTech édite le logiciel et **n'exploite aucun service** qui recevrait vos
données. Pour toute question sur vos données elles-mêmes — accès, rectification,
effacement — adressez-vous à la bibliothèque de votre établissement.

## 2. Ce que l'application envoie, et à qui

Tout ce qui suit part **vers le serveur de votre établissement, et nulle part
ailleurs** :

| Quand | Ce qui est envoyé |
|---|---|
| Connexion | votre adresse électronique et votre mot de passe |
| Enregistrement de l'appareil | la **clé publique** de votre appareil, le type d'appareil (`android`), et éventuellement un libellé |
| Emprunt d'un document hors ligne | l'identifiant du document et celui de votre appareil |
| Consultation | vos recherches dans le catalogue, l'identifiant des notices ouvertes, vos prêts et réservations |

⚠ **Votre clé privée n'est jamais envoyée.** Elle est créée dans le coffre
matériel de votre téléphone (Android Keystore), elle ne peut pas en être extraite
— ni par l'application, ni par nous, ni par votre établissement.

## 3. Ce que l'application garde sur votre téléphone

Tout est rangé dans l'espace **privé** de l'application, inaccessible aux autres
applications :

- votre **session** (identifiant, établissement, nom affiché, jeton) — chiffrée
  en AES-256-GCM avec une clé du coffre matériel ;
- votre **bibliothèque hors ligne** : les licences de lecture et le chemin des
  documents — chiffrée de la même façon ;
- les **documents téléchargés**, qui restent **chiffrés** sur le téléphone et ne
  sont déchiffrés qu'en mémoire, le temps de l'affichage ;
- les **couvertures** déjà vues (200 au maximum), pour ne pas les redemander ;
- l'**identifiant d'appareil** attribué par votre établissement.

**Rien de tout cela n'est copié ailleurs.** L'application interdit explicitement
la sauvegarde automatique de ces données (`allowBackup="false"`) : elles ne
partent ni vers Google Drive, ni vers un autre téléphone.

**Pour tout effacer** : « Se déconnecter » dans l'application supprime la
session, les licences, les documents téléchargés et les couvertures. Désinstaller
l'application efface également tout.

## 4. Ce que l'application ne fait PAS

- **Aucune publicité**, aucun pistage publicitaire, aucun identifiant publicitaire.
- **Aucune mesure d'audience** : pas de Google Analytics, pas de Firebase
  Analytics, pas de Crashlytics, aucun projet Firebase configuré.
- **Aucune localisation**, aucun accès aux contacts, aux photos, aux fichiers, au
  microphone ni au carnet d'adresses.
- **Aucune notification distante** : les rappels d'échéance de prêt sont calculés
  et affichés **par votre téléphone**, localement. Aucun service de notification
  push n'est utilisé.
- **Aucun partage avec un tiers.** Nous ne vendons, ne louons et ne transmettons
  aucune donnée, parce que nous n'en recevons aucune.
- **Aucun compte chez nous** : vous n'avez pas de compte ResurgiTech.

## 5. La caméra

L'application demande l'accès à la caméra **uniquement** pour lire le QR affiché
au comptoir de votre bibliothèque, qui désigne votre établissement.

⚠ **Le décodage se fait entièrement sur votre téléphone** : le modèle de lecture
de codes est embarqué dans l'application. **Aucune image, aucune photo, aucune
vidéo n'est enregistrée ni envoyée** — ni à nous, ni à votre établissement, ni à
quiconque. Vous pouvez refuser cette permission : la saisie du code de
l'établissement au clavier reste possible et équivalente.

## 6. Composants tiers

L'application embarque le lecteur de codes-barres **Google ML Kit** pour le scan
du QR. Son modèle de reconnaissance est **inclus dans l'application** et
fonctionne hors ligne.

⚠ **À connaître, et nous préférons le dire** : ce composant s'accompagne de
bibliothèques Google (services Google Play, transport de diagnostics) qui peuvent
transmettre à Google des **mesures techniques d'utilisation du composant** —
indépendamment de nous, et sans contenu de vos images ni de vos lectures. Nous ne
configurons, n'exploitons ni ne consultons aucune de ces mesures. Le
comportement de ces bibliothèques relève des
[conditions de Google](https://policies.google.com/privacy).

L'application embarque également **PDFium** (lecture des documents) et
**flutter_local_notifications** (rappels locaux), qui ne communiquent avec
aucun serveur.

## 7. Enfants

L'application s'adresse aux lecteurs inscrits dans un établissement
d'enseignement. Elle ne collecte sciemment aucune donnée d'enfant de moins de 13
ans et ne contient aucun contenu destiné aux enfants.

## 8. Sécurité

- Le trafic est **chiffré en HTTPS** et l'application **refuse le trafic en
  clair** ; elle refuse également qu'un serveur sécurisé désigne une interface
  non chiffrée.
- Les documents sont chiffrés **sur le téléphone** par une clé qui ne quitte
  jamais le coffre matériel.
- La **capture d'écran et l'enregistrement d'écran sont bloqués** dans
  l'application, et son contenu n'apparaît pas dans la liste des applications
  récentes.
- L'application est **libre** (AGPL-3.0) : son code est public et vérifiable.

## 9. Modifications

Toute modification de cette politique sera publiée à cette même adresse, avec sa
date. Les changements substantiels seront annoncés dans les notes de version de
l'application.

## 10. Nous écrire

**security@gafeso.org** — ResurgiTech SARL, Ouagadougou, Burkina Faso.

Pour une demande portant sur **vos données** (accès, rectification, effacement),
adressez-vous à la bibliothèque de votre établissement, qui en est responsable.
