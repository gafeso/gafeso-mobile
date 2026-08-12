# Contribuer à Gafeso Mobile

Merci de l'intérêt porté à Gafeso. Ce dépôt fait partie du projet open-source **Gafeso**,
édité par ResurgiTech, sous licence **AGPL-3.0**.

## Mise en place

- Flutter + Android SDK/NDK, **minSdk 33** (Android 13).
- `flutter pub get`, puis `flutter run` / `flutter build apk`.
- Le lecteur natif (Kotlin/NDK + PDFium) est sous `android/`.

## Conventions

- **Messages de commit en français**, clairs et à granularité fine (un bloc cohérent par
  commit).
- **Tests verts avant tout commit** ; `flutter analyze` sans avertissement.
- Ouvrez une **Pull Request** ciblant la branche de développement ; décrivez le quoi et le
  pourquoi.
- Pour un changement conséquent, ouvrez d'abord une **issue** pour en discuter la direction.

## Origine des contributions (DCO)

Ce projet utilise le **Developer Certificate of Origin** : en signant vos commits, vous
certifiez avoir le droit de soumettre votre code sous la licence du projet.

```bash
git commit -s        # ajoute la ligne "Signed-off-by: Nom <email>"
```

Toute contribution est acceptée sous **AGPL-3.0**.

## Sécurité

Ne signalez **jamais** une faille de sécurité via une issue publique. Suivez la procédure de
[`SECURITY.md`](SECURITY.md).

## Ce qui aide le plus

- Rapports de bugs reproductibles (modèle d'appareil, version Android, étapes).
- Retours de terrain sur les appareils d'entrée de gamme (le parc cible).
- Traductions et accessibilité.
