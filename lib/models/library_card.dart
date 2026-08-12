import 'package:flutter/foundation.dart';

/// Carte de lecteur — forme relevée sur `GET /reader/card` en fonctionnement.
///
/// Le code-barres est celui de l'ADHÉRENT (`LEC-…`), pas le matricule : c'est
/// lui que la circulation attend à l'emprunt. Prouvé de bout en bout côté
/// serveur — un checkout avec ce code est accepté.
@immutable
class LibraryCard {
  const LibraryCard({
    required this.barcode,
    required this.category,
    required this.symbology,
    required this.displayName,
  });

  final String barcode;
  final String category;

  /// Symbologie donnée par le SERVEUR. On ne la devine pas : une carte rendue
  /// dans une autre serait illisible au comptoir sans que rien ne l'explique.
  final String symbology;

  final String displayName;

  static LibraryCard fromJson(Object json) {
    final j = json as Map<String, dynamic>;
    return LibraryCard(
      barcode: j['barcode'] as String? ?? '',
      category: j['category'] as String? ?? '',
      symbology: j['symbology'] as String? ?? 'code128',
      displayName: j['displayName'] as String? ?? '',
    );
  }

  Object toJson() => {
        'barcode': barcode,
        'category': category,
        'symbology': symbology,
        'displayName': displayName,
      };
}
