import 'package:flutter/foundation.dart';

/// Modèles du catalogue (OPAC).
///
/// Formes RELEVÉES sur l'API en fonctionnement (`GET /opac/search`,
/// `GET /opac/records/:id`), pas déduites d'une documentation.

/// Un résultat de recherche.
@immutable
class SearchHit {
  const SearchHit({
    required this.id,
    required this.title,
    this.author,
    this.category,
    this.publishYear,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String? author;
  final String? category;
  final int? publishYear;

  /// Couverture — souvent absente. Chargée en différé et en petite taille :
  /// un étudiant en 3G paie ses données, et une liste de résultats qui tire
  /// vingt images pleine résolution coûte plus cher que tout le reste réuni.
  final String? coverUrl;

  /// Ligne secondaire : auteur · année. On n'affiche pas les champs vides,
  /// ni les séparateurs orphelins qu'ils laisseraient.
  String get subtitle =>
      [author, publishYear?.toString()].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  static SearchHit fromJson(Map<String, dynamic> j) => SearchHit(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Sans titre',
        author: (j['author'] as String?)?.trim().isEmpty ?? true ? null : j['author'] as String,
        category: j['category'] as String?,
        publishYear: (j['publishYear'] as num?)?.toInt(),
        coverUrl: j['coverUrl'] as String?,
      );
}

/// Une page de résultats.
@immutable
class SearchPage {
  const SearchPage({
    required this.hits,
    required this.totalHits,
    required this.page,
    required this.totalPages,
  });

  final List<SearchHit> hits;
  final int totalHits;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;

  static SearchPage fromJson(Object json) {
    final j = json as Map<String, dynamic>;
    return SearchPage(
      hits: ((j['hits'] as List?) ?? const [])
          .map((e) => SearchHit.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalHits: (j['totalHits'] as num?)?.toInt() ?? 0,
      page: (j['page'] as num?)?.toInt() ?? 1,
      totalPages: (j['totalPages'] as num?)?.toInt() ?? 1,
    );
  }

  /// Fusion pour le défilement : la page suivante s'ajoute, elle ne remplace pas.
  SearchPage merge(SearchPage suivante) => SearchPage(
        hits: [...hits, ...suivante.hits],
        totalHits: suivante.totalHits,
        page: suivante.page,
        totalPages: suivante.totalPages,
      );
}

/// Un exemplaire physique.
@immutable
class Item {
  const Item({required this.barcode, required this.status, this.location, this.callNumber});

  final String barcode;
  final String status;
  final String? location;
  final String? callNumber;

  bool get available => status == 'AVAILABLE';

  /// Libellé d'état lisible. `CHECKED_OUT` ne dit rien à un étudiant ; « en
  /// prêt » si. Un statut inconnu est rendu tel quel plutôt que traduit en
  /// « indisponible » — inventer une signification serait pire que l'afficher.
  String get statusLabel => switch (status) {
        'AVAILABLE' => 'Disponible',
        'CHECKED_OUT' => 'En prêt',
        'RESERVED' => 'Réservé',
        'LOST' => 'Perdu',
        'MISSING' => 'Manquant',
        'DAMAGED' => 'Endommagé',
        _ => status,
      };

  static Item fromJson(Map<String, dynamic> j) => Item(
        barcode: j['barcode'] as String? ?? '',
        status: j['status'] as String? ?? 'UNKNOWN',
        location: j['location'] as String?,
        callNumber: j['callNumber'] as String?,
      );
}

/// Fiche notice détaillée.
@immutable
class RecordDetail {
  const RecordDetail({
    required this.id,
    required this.title,
    required this.items,
    this.author,
    this.summary,
    this.publisher,
    this.publishYear,
    this.category,
    this.hasDigitalCopy = false,
  });

  final String id;
  final String title;
  final String? author;
  final String? summary;
  final String? publisher;
  final int? publishYear;
  final String? category;
  final List<Item> items;

  /// Un document numérique existe pour cette notice — c'est le lien avec la
  /// lecture hors ligne, la raison d'être du produit.
  final bool hasDigitalCopy;

  int get availableCount => items.where((i) => i.available).length;

  /// Peut-on réserver ? Seulement s'il existe des exemplaires ET qu'aucun n'est
  /// libre : proposer de réserver un ouvrage disponible enverrait le lecteur
  /// attendre alors qu'il peut l'emprunter tout de suite.
  bool get canReserve => items.isNotEmpty && availableCount == 0;

  static RecordDetail fromJson(Object json) {
    final j = json as Map<String, dynamic>;
    return RecordDetail(
      id: j['id'] as String,
      title: j['title'] as String? ?? 'Sans titre',
      author: j['author'] as String?,
      summary: j['summary'] as String?,
      publisher: j['publisher'] as String?,
      publishYear: (j['publishYear'] as num?)?.toInt(),
      category: j['category'] as String?,
      items: ((j['items'] as List?) ?? const [])
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasDigitalCopy: j['digitalCopy'] != null,
    );
  }
}
