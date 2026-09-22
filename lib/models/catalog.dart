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

/// Une contribution à l'œuvre : qui, et à quel titre.
///
/// ⚠ LE RÔLE COMPTE AUTANT QUE LE NOM sur un dépôt universitaire. Le champ
/// `author` que l'app affichait seul est une dénormalisation du PREMIER auteur
/// principal ; il laisse de côté le directeur de mémoire, présent sur 211 des
/// 480 notices mesurées. Sur une thèse, savoir qui a dirigé le travail est une
/// information de premier plan — c'est par là qu'on cherche un encadrant.
@immutable
class Contributor {
  const Contributor({required this.name, required this.role});

  final String name;

  /// `AUTEUR_PRINCIPAL` · `AUTEUR_SECONDAIRE` · `DIRECTEUR_MEMOIRE`.
  final String role;

  /// Libellé lisible. Une constante technique affichée telle quelle
  /// (« DIRECTEUR_MEMOIRE ») est du jargon de base de données, pas une réponse.
  String get roleLisible => switch (role) {
        'AUTEUR_PRINCIPAL' => 'Auteur',
        'AUTEUR_SECONDAIRE' => 'Co-auteur',
        'DIRECTEUR_MEMOIRE' => 'Direction',
        _ => role,
      };

  bool get estDirection => role == 'DIRECTEUR_MEMOIRE';

  static Contributor? fromJson(Object? j) {
    if (j is! Map) return null;
    final n = j['name'] as String?;
    if (n == null || n.isEmpty) return null;
    return Contributor(name: n, role: j['role'] as String? ?? '');
  }
}

/// Disponibilité telle que le SERVEUR la calcule.
///
/// ⚠ L'app la recalculait depuis `items`. Refaire côté client un calcul que le
/// serveur publie, c'est deux vérités possibles pour une question — et c'est
/// `borrowable` qui tranche l'emprunt, pas notre arithmétique.
@immutable
class Availability {
  const Availability({required this.totalItems, required this.available, required this.borrowable});

  final int totalItems;
  final int available;
  final bool borrowable;

  static Availability? fromJson(Object? j) {
    if (j is! Map) return null;
    return Availability(
      totalItems: (j['totalItems'] as num?)?.toInt() ?? 0,
      available: (j['available'] as num?)?.toInt() ?? 0,
      borrowable: j['borrowable'] == true,
    );
  }
}

/// D'où vient cette notice, quand elle ne vient pas d'ici.
///
/// ⚠ INVARIANT P7-3 — « ce qui arrive par moissonnage reste marqué comme tel ».
/// Le serveur sert cette clé à TOUS, membre ou non, précisément pour que rien
/// ne puisse se présenter comme catalogué sur place alors qu'il vient d'une
/// autre école. Un client qui ne lit pas la clé défait la décision aussi
/// sûrement que si le serveur ne l'avait jamais servie.
@immutable
class Provenance {
  const Provenance({required this.sourceName, this.oaiIdentifier, this.lien});

  /// Nom de l'école d'origine — c'est ce qu'un lecteur comprend.
  final String sourceName;

  /// Identifiant OAI dans le dépôt d'origine. Technique : affiché en second.
  final String? oaiIdentifier;

  /// Lien vers la notice à l'origine, relu du Dublin Core conservé à
  /// l'ingestion. Absent pour certaines sources : alors on n'invente pas.
  final String? lien;

  static Provenance? fromJson(Object? json) {
    if (json is! Map) return null;
    final source = json['source'];
    final nom = source is Map ? source['name'] as String? : null;
    if (nom == null || nom.isEmpty) return null;
    return Provenance(
      sourceName: nom,
      oaiIdentifier: json['oaiIdentifier'] as String?,
      lien: json['lien'] as String?,
    );
  }
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
    this.digitalFormat,
    this.embargoUntil,
    this.provenance,
    this.recordType,
    this.titleComplement,
    this.isbn,
    this.language,
    this.publicationCity,
    this.defenseUniversity,
    this.defensePlace,
    this.coverUrl,
    this.contributors = const [],
    this.keywords = const [],
    this.availability,
  });

  final String id;
  final String title;
  final String? author;
  final String? summary;
  final String? publisher;
  final int? publishYear;
  final String? category;
  final List<Item> items;

  /// Format du document numérique attaché (`PDF`, `EPUB`…), `null` s'il n'y en
  /// a pas. On garde le FORMAT et non un booléen : ce que l'app peut promettre
  /// en dépend — seul le PDF descend sur l'appareil (`myDocuments` filtre
  /// dessus). Réduire cette information à « il y a un fichier » revient à
  /// promettre au lecteur une lecture hors ligne qui n'aura pas lieu.
  final String? digitalFormat;

  /// Nature du document (`these`, `memoire`, `ouvrage`, `publication`).
  final String? recordType;

  /// Sous-titre. 106 notices sur 480 en portent un, et il porte souvent la
  /// précision qui distingue deux travaux au titre proche.
  final String? titleComplement;

  final String? isbn;
  final String? language;
  final String? publicationCity;

  /// Université de soutenance et lieu — le cœur d'un dépôt de thèses.
  /// Renseignés sur exactement les 211 thèses et mémoires du fonds mesuré.
  final String? defenseUniversity;
  final String? defensePlace;

  final String? coverUrl;

  /// Auteurs et direction, dans l'ordre de position servi par le serveur.
  final List<Contributor> contributors;

  /// Mots-clés d'indexation : ce par quoi un lecteur retrouve un sujet.
  final List<String> keywords;

  /// Disponibilité calculée par le serveur. `null` pour un visiteur non membre.
  final Availability? availability;

  /// Libellé lisible du type. La base stocke des constantes en minuscules ;
  /// « these » affiché tel quel n'est pas français.
  String? get typeLisible => switch (recordType) {
        'these' => 'Thèse',
        'memoire' => 'Mémoire',
        'ouvrage' => 'Ouvrage',
        'publication' => 'Publication',
        null => null,
        _ => recordType,
      };

  /// Un travail universitaire soutenu : c'est ce qui justifie d'afficher le
  /// bloc de soutenance et la direction.
  bool get estTravailUniversitaire =>
      recordType == 'these' || recordType == 'memoire';

  /// Provenance, si la notice a été moissonnée depuis une autre école.
  /// `null` = notice catalogée ici. Voir [Provenance] : ne pas la lire revient
  /// à défaire côté client une décision tenue côté serveur.
  final Provenance? provenance;

  /// Date de levée d'embargo, quand la notice en porte un. Les métadonnées sont
  /// publiques, le fichier non : servir la date permet de dire POURQUOI l'accès
  /// est refusé, au lieu de laisser conclure à une panne.
  final DateTime? embargoUntil;

  /// Un document numérique existe pour cette notice.
  bool get hasDigitalCopy => digitalFormat != null;

  /// L'embargo court-il encore ? Comparé à l'instant fourni — jamais à
  /// `DateTime.now()` en dur, pour que ce soit testable.
  bool aUnEmbargoActif(DateTime maintenant) =>
      embargoUntil != null && embargoUntil!.isAfter(maintenant);

  /// Le document peut-il réellement descendre sur l'appareil ? C'est la seule
  /// condition qui autorise à parler de « lecture hors connexion ».
  bool estTelechargeable(DateTime maintenant) =>
      digitalFormat?.toUpperCase() == 'PDF' && !aUnEmbargoActif(maintenant);

  /// Nombre d'exemplaires libres — celui du SERVEUR quand il le publie, sinon
  /// calculé localement (visiteur non membre, ou réponse ancienne).
  int get availableCount =>
      availability?.available ?? items.where((i) => i.available).length;

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
      // ⚠ La clé servie est `fileFormat` (contrat OPAC), pas `format`.
      digitalFormat: (j['digitalCopy'] as Map<String, dynamic>?)?['fileFormat'] as String?,
      embargoUntil: DateTime.tryParse(j['embargoUntil'] as String? ?? ''),
      provenance: Provenance.fromJson(j['provenance']),
      recordType: j['recordType'] as String?,
      titleComplement: j['titleComplement'] as String?,
      isbn: j['isbn'] as String?,
      language: j['language'] as String?,
      publicationCity: j['publicationCity'] as String?,
      defenseUniversity: j['defenseUniversity'] as String?,
      defensePlace: j['defensePlace'] as String?,
      coverUrl: j['coverUrl'] as String?,
      contributors: ((j['contributors'] as List?) ?? const [])
          .map(Contributor.fromJson)
          .whereType<Contributor>()
          .toList(),
      keywords: ((j['keywords'] as List?) ?? const []).whereType<String>().toList(),
      availability: Availability.fromJson(j['availability']),
    );
  }
}
