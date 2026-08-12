# Identité visuelle Gafeso

Le logo dit ce qu'est le produit : un **toit** posé sur un **livre ouvert** —
« la maison des livres », sens du mot *gafeso* en dioula.

Ces fichiers sont la **source de vérité**. Le texte y est déjà vectorisé, le
fond est transparent, et aucune police externe n'est requise. **Ne les
régénérez pas** : un rendu refait à partir d'une police absente de la machine
produirait un logo différent sans que personne ne s'en aperçoive.

## Quelle version, dans quel contexte

| Version | Fichier | Où |
|---|---|---|
| **Horizontal** | `gafeso_horizontal.svg` | En-tête de site, README, signature d'email, papier à en-tête. C'est la version par défaut dès qu'on dispose de largeur. |
| **Vertical détaillé** | `gafeso_vertical_detaille.svg` | Affiches, couvertures, écran de démarrage — partout où l'on a de la hauteur et au moins ~120 px de large. |
| **Simplifié + nom** | `gafeso_simplifie_avec_nom.svg` | Formats intermédiaires où le détail du toit se perd mais où le nom doit rester. |
| **Icône simplifiée** | `gafeso_icone_simplifiee.svg` | Icône d'application, favicon, avatar. **La seule version admise sous 48 px.** |
| **Monochrome** | `gafeso_monochrome.svg` | Fax, tampon, gravure, impression une couleur, fond de couleur forte. |

**Sous 48 px, seule l'icône simplifiée est lisible.** La version détaillée porte
une fenêtre à quatre carreaux et trois filets sur le livre : à petite taille ils
fusionnent en une tache. Ce n'est pas une question de goût — c'est ce qui décide
qu'un utilisateur reconnaisse ou non son application dans une grille d'icônes.

## Couleurs

| | Hex | Rôle |
|---|---|---|
| Vert | `#1B5E3F` | Toit, mot « Gafe ». Couleur principale. |
| Orange | `#E07A2B` | Page gauche du livre, syllabe « so ». |
| Orange foncé | `#C4641F` | Page droite — l'ombre qui donne le volume. |

Le vert porte l'identité, l'orange l'accent. Un aplat de vert avec le logo
monochrome blanc est le repli quand le fond est coloré.

## Zone de respiration

Réservez autour du logo une marge vide égale à **la hauteur du toit**. Rien n'y
entre : ni texte, ni filet, ni bord de bloc. C'est la règle qui empêche le logo
de paraître écrasé dans un en-tête serré.

Taille minimale : **24 px** de haut pour l'icône simplifiée, **80 px** de large
pour l'horizontal. En dessous, le nom cesse d'être lisible.

## Icône adaptative Android

Attention particulière, qui ne se déduit d'aucun fichier : Android **masque**
l'icône selon le lanceur — cercle, carré arrondi, goutte. Une forme qui tient
parfaitement dans le carré source peut se faire couper le toit une fois masquée.

Le premier plan doit donc rester dans le **cercle intérieur** (66 % de la
largeur), et la vérification se fait **sur l'appareil, à l'écran d'accueil** —
pas sur les fichiers générés, qui paraissent toujours corrects.
