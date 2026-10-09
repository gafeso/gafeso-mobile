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
    // Les tailles suivent la HAUTEUR : la même couverture sert la vignette d'une
    // liste et le bloc d'une fiche, sans deux jeux de constantes à tenir
    // d'accord.
    final t = hauteur * 0.082;
    final s = hauteur * 0.055;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            titre,
            maxLines: hauteur > 160 ? 5 : 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: t,
              height: 1.22,
              fontWeight: FontWeight.w700,
              color: encre,
            ),
          ),
        ),
        if (avecAuteur && auteur != null && auteur!.trim().isNotEmpty) ...[
          SizedBox(height: hauteur * 0.02),
          Text(
            auteur!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: s,
              height: 1.2,
              // ⚠ Pas une encre plus pâle : sur ces fonds, un blanc atténué
              // retombe sous le seuil. On distingue par la GRAISSE et la
              // taille, pas par le contraste.
              color: encre,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
        SizedBox(height: hauteur * 0.03),
        Row(
          children: [
            if (type != null && type!.trim().isNotEmpty)
              Flexible(
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: hauteur * 0.028,
                    vertical: hauteur * 0.012,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: encre, width: 1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    type!.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: hauteur * 0.040,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600,
                      color: encre,
                    ),
                  ),
                ),
              ),
            if (annee != null) ...[
              const Spacer(),
              Text(
                '$annee',
                style: TextStyle(
                  fontSize: hauteur * 0.046,
                  fontWeight: FontWeight.w500,
                  color: encre,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
