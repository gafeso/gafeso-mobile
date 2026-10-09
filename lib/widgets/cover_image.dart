import 'dart:io';

import 'package:flutter/material.dart';


import '../cache/cover_cache.dart';
import 'couverture_generee.dart';

/// Couverture d'une notice, ou son substitut.
///
/// ⚠ RÈGLE : cet écran s'affiche ENTIÈREMENT sans elle. Le substitut est posé
/// d'emblée et l'image le remplace si elle arrive — jamais de rectangle vide en
/// attente, jamais de roue qui tourne, jamais d'icône « image cassée ». Sur un
/// fonds sans couverture ou en 3G, la liste reste lisible et régulière.
///
/// Le substitut n'est pas un carré gris : il porte l'initiale du titre, ce qui
/// aide l'œil à repérer une ligne dans une liste bien plus qu'une forme neutre.
class CoverImage extends StatefulWidget {
  const CoverImage({
    super.key,
    required this.coverUrl,
    required this.titre,
    this.cache,
    this.origine,
    this.largeur = 44,
    this.hauteur = 62,
    this.auteur,
    this.type,
    this.annee,
    this.domaine,
    this.avecAuteur = true,
  });

  final String? coverUrl;
  final String titre;

  /// Ce que la couverture DESSINÉE affiche quand aucune image n'est rendue.
  /// Tous facultatifs : un champ absent n'apparaît pas, il n'est pas inventé.
  final String? auteur;
  final String? type;
  final int? annee;
  final String? domaine;

  /// Voir `CouvertureGeneree.avecAuteur`.
  final bool avecAuteur;

  /// `null` = pas de cache disponible (tests, ou app non configurée) : on
  /// affiche le substitut sans jamais tenter le réseau.
  final CoverCache? cache;

  /// Origine du serveur, pour résoudre les chemins relatifs du contrat.
  final String? origine;

  final double largeur;
  final double hauteur;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  File? _fichier;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void didUpdateWidget(CoverImage ancien) {
    super.didUpdateWidget(ancien);
    if (ancien.coverUrl != widget.coverUrl) _charger();
  }

  Future<void> _charger() async {
    final cache = widget.cache;
    final uri = CoverCache.resoudre(widget.coverUrl, origine: widget.origine);
    if (cache == null || uri == null) return;

    // Le cache répond sans réseau ni délai : on l'affiche AVANT toute requête,
    // pour que le défilement d'une liste déjà parcourue soit instantané.
    final dejaLa = cache.enCache(uri);
    if (dejaLa != null) {
      if (mounted) setState(() => _fichier = dejaLa);
      return;
    }

    final f = await cache.obtenir(uri);
    if (f != null && mounted) setState(() => _fichier = f);
  }

  @override
  Widget build(BuildContext context) {
    final f = _fichier;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: widget.largeur,
        height: widget.hauteur,
        child: f == null
            ? _substitut(context)
            : Image.file(
                f,
                fit: BoxFit.cover,
                width: widget.largeur,
                height: widget.hauteur,
                // Un fichier illisible (téléchargement tronqué, format
                // inattendu) retombe sur le substitut au lieu de peindre une
                // icône d'erreur au milieu d'une liste.
                errorBuilder: (c, _, _) => _substitut(c),
              ),
      ),
    );
  }

  /// ⚠ Le substitut n'est plus un carré gris à initiale : c'est une couverture
  /// composée du texte de la notice. Mesure à l'appui — sur ce fonds, 480
  /// notices sur 480 pointent un SVG non rendu, partagé par quatre-vingts
  /// notices à la fois. Voir `CouvertureGeneree`.
  Widget _substitut(BuildContext context) => CouvertureGeneree(
        titre: widget.titre,
        auteur: widget.auteur,
        type: widget.type,
        annee: widget.annee,
        domaine: widget.domaine,
        avecAuteur: widget.avecAuteur,
        largeur: widget.largeur,
        hauteur: widget.hauteur,
      );
}
