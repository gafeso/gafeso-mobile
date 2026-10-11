import 'package:flutter/material.dart';

import '../theme/gafeso_theme.dart';

/// Couverture **dessinée** d'une notice — titre, auteur, type, année.
///
/// ⚠ CE N'EST PAS UN SUBSTITUT DÉGRADÉ, C'EST LE CAS COURANT, et c'est une
/// mesure qui le décide (relevé du 09/10/2026, fonds de démonstration) :
/// 480 notices sur 480 portent une `coverUrl`, toutes pointent un **SVG** que
/// Flutter ne rend pas sans dépendance, et il n'existe que **6 fichiers
/// distincts** pour ces 480 notices. Même avec un moteur SVG, quatre-vingts
/// notices partageraient la même image : elle ne distinguerait rien.
///
/// Une couverture composée du texte de la notice, elle, distingue — et elle
/// coûte zéro octet de réseau, s'affiche hors ligne, et ne peut pas échouer.
///
/// ⚠ ELLE N'INVENTE RIEN. Pas d'étoiles, pas de note, pas de durée de lecture :
/// on n'affiche que des champs que la notice porte réellement. Un champ absent
/// disparaît, il n'est pas remplacé par un tiret ni par une valeur plausible.
class CouvertureGeneree extends StatelessWidget {
  const CouvertureGeneree({
    super.key,
    required this.titre,
    required this.largeur,
    required this.hauteur,
    this.auteur,
    this.type,
    this.annee,
    this.domaine,
    this.avecAuteur = true,
  });

  final String titre;
  final String? auteur;
  final String? type;
  final int? annee;

  /// Décide la teinte. Voir `teinteDomaine` : les travaux d'un même champ se
  /// reconnaissent en bloc dans une liste.
  final String? domaine;

  final double largeur;
  final double hauteur;

  /// ⚠ L'auteur se tait quand il est DÉJÀ À CÔTÉ. Sur la fiche, la couverture
  /// jouxte un bloc titre-auteur : l'imprimer sur la couverture le montrait
  /// deux fois à dix millimètres d'écart. Dans une liste, au contraire, la
  /// couverture est seule à identifier le document, et l'auteur y reste.
  final bool avecAuteur;

  /// En dessous de cette hauteur, le texte serait de la poussière : on ne garde
  /// que l'initiale. Mesuré sur la vignette de liste (62 dp) et sur la fiche
  /// (220 dp) — le seuil est celui où le titre cesse de tenir deux mots.
  static const double _seuilTexte = 80;

  @override
  Widget build(BuildContext context) {
    final fond = teinteDomaine(domaine);
    const encre = surCouverture;
    final petite = hauteur < _seuilTexte;

    return Container(
      width: largeur,
      height: hauteur,
      color: fond,
      child: Stack(
        children: [
          // Le dos du livre : un filet orange collé au bord gauche. C'est le
          // seul ornement, et il dit « livre » d'un coup d'œil même en vignette.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: (largeur * 0.055).clamp(2.0, 6.0),
            child: const ColoredBox(color: GafesoMarque.orange),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(largeur * 0.14, hauteur * 0.08, largeur * 0.09, hauteur * 0.07),
            child: petite ? _initiale(encre) : _texte(encre),
          ),
        ],
      ),
    );
  }

  Widget _initiale(Color encre) => Center(
        child: Text(
          titre.trim().isEmpty ? '?' : titre.trim().characters.first.toUpperCase(),
          style: TextStyle(
            fontSize: hauteur * 0.40,
            fontWeight: FontWeight.w700,
            color: encre,
            height: 1,
          ),
        ),
      );

  Widget _texte(Color encre) {
    // ⚠ LES RAPPORTS SONT CALÉS SUR LA TUILE DE GRILLE (ratio 0,72), puis
    // suivent la hauteur ailleurs. Deux jeux de constantes — un pour la grille,
    // un pour la fiche — finiraient par diverger ; ici une seule maquette sert
    // les deux tailles, et la grille est celle qu'on a dessinée.
    final t = hauteur * 0.082; // titre
    final s = hauteur * 0.050; // auteur · année
    final c = hauteur * 0.046; // type, en capitales
    final annexe = [
      if (auteur != null && auteur!.trim().isNotEmpty && avecAuteur) auteur!.trim(),
      if (annee != null) '$annee',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (type != null && type!.trim().isNotEmpty) ...[
          Text(
            type!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: c,
              letterSpacing: c * 0.14,
              fontWeight: FontWeight.w700,
              color: encre,
              height: 1,
            ),
          ),
          SizedBox(height: hauteur * 0.035),
        ],
        Expanded(
          child: Text(
            titre,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              // ⚠ SÉRIF, et c'est la famille GÉNÉRIQUE du système : aucun
              // fichier de police embarqué. Une fonte de 300 Ko pour quatre
              // lignes de titre coûterait plus cher que tout le reste de
              // l'application, sur des appareils qu'on a choisi de ménager.
              fontFamily: 'serif',
              fontSize: t,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: encre,
            ),
          ),
        ),
        if (annexe.isNotEmpty) ...[
          // Le filet : translucide, donc il suit la teinte du domaine au lieu
          // de poser un blanc franc qui trancherait sur les fonds les plus
          // clairs de la palette.
          Container(
            height: 1,
            margin: EdgeInsets.only(bottom: hauteur * 0.035),
            color: encre.withValues(alpha: 0.35),
          ),
          Text(
            annexe,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: s,
              height: 1.2,
              color: encre,
            ),
          ),
        ],
      ],
    );
  }
}
