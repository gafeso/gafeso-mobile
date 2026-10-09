import 'dart:convert';

import 'package:flutter/services.dart';

/// Un document rendu disponible hors-ligne : sa licence (nécessaire pour ouvrir SANS réseau)
/// et le chemin du blob chiffré.
class LocalDocument {
  const LocalDocument({
    required this.docId,
    required this.title,
    required this.licenseId,
    required this.licenseBody,
    required this.signature,
    required this.licensePublicKey,
    required this.wrappedCek,
    required this.blobPath,
    this.lastStatus = 'active',
    this.auteur,
    this.domaine,
    this.annee,
    this.type,
  });

  final String docId;
  final String title;
  final String licenseId;
  final String licenseBody; // JSON canonique-able du corps signé
  final String signature;
  final String licensePublicKey;
  final String wrappedCek; // enveloppe EC-KEM {v, epk, nonce, ct}
  final String blobPath;
  final String lastStatus;

  /// ⚠ MÉTADONNÉES RECOPIÉES AU TÉLÉCHARGEMENT, et c'est une mesure qui l'impose.
  /// `GET /offline/my-documents` ne rend que `{docId, title, fileFormat}` —
  /// relevé dans `offline-licenses.service.ts` le 09/10/2026. Sans ces champs,
  /// l'étagère ne pourrait composer que des couvertures au titre seul, et la
  /// section « Lectures en cours » n'aurait ni auteur ni domaine à montrer.
  ///
  /// Tous facultatifs : l'étagère sait télécharger un document qu'on n'a ouvert
  /// nulle part, et il n'y a alors rien à recopier. Un champ absent n'est pas
  /// inventé. La demande d'enrichir la route est portée au backend.
  final String? auteur;
  final String? domaine;
  final int? annee;
  final String? type;

  /// Date de fin de bail, LUE DU CORPS DE LICENCE déjà présent sur l'appareil.
  ///
  /// ⚠ Elle était là depuis le début et personne ne la regardait. L'étagère
  /// annonçait « Disponible hors ligne » pour un document que le lecteur natif
  /// refusait ensuite d'ouvrir — même motif que la carte verte de la fiche :
  /// l'information est dans la réponse, l'écran la jette, puis il promet ce qui
  /// en dépend.
  ///
  /// `null` si le corps est illisible ou sans date : on n'invente alors aucune
  /// expiration, et le document reste présenté comme lisible — c'est le natif
  /// qui tranche, lui seul vérifie la signature.
  DateTime? get expiresAt {
    try {
      final m = (jsonDecode(licenseBody) as Map).cast<String, dynamic>();
      return DateTime.tryParse(m['expiresAt'] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Le bail a-t-il expiré à l'instant fourni ? Jamais `DateTime.now()` en dur :
  /// une date de référence en paramètre est ce qui rend ceci testable.
  bool estExpiree(DateTime maintenant) {
    final fin = expiresAt;
    return fin != null && fin.isBefore(maintenant);
  }

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'title': title,
        if (auteur != null) 'auteur': auteur,
        if (domaine != null) 'domaine': domaine,
        if (annee != null) 'annee': annee,
        if (type != null) 'type': type,
        'licenseId': licenseId,
        'licenseBody': licenseBody,
        'signature': signature,
        'licensePublicKey': licensePublicKey,
        'wrappedCek': wrappedCek,
        'blobPath': blobPath,
        'lastStatus': lastStatus,
      };

  factory LocalDocument.fromJson(Map<String, dynamic> j) => LocalDocument(
        docId: j['docId'] as String,
        title: j['title'] as String,
        licenseId: j['licenseId'] as String,
        licenseBody: j['licenseBody'] as String,
        signature: j['signature'] as String,
        licensePublicKey: j['licensePublicKey'] as String,
        wrappedCek: j['wrappedCek'] as String,
        blobPath: j['blobPath'] as String,
        lastStatus: (j['lastStatus'] as String?) ?? 'active',
        auteur: j['auteur'] as String?,
        domaine: j['domaine'] as String?,
        annee: (j['annee'] as num?)?.toInt(),
        type: j['type'] as String?,
      );

  LocalDocument copyWith({String? lastStatus}) => LocalDocument(
        docId: docId,
        title: title,
        licenseId: licenseId,
        licenseBody: licenseBody,
        signature: signature,
        licensePublicKey: licensePublicKey,
        wrappedCek: wrappedCek,
        blobPath: blobPath,
        lastStatus: lastStatus ?? this.lastStatus,
      );
}

/// Bibliothèque locale — **chiffrée par le keystore** (canal `com.gafeso/secure`) : elle
/// contient les licences, donc les CEK enveloppées. Persister la licence est ce qui rend la
/// lecture possible **sans réseau** ; le blob seul ne suffit pas.
class LibraryStore {
  LibraryStore({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('com.gafeso/secure');

  static const _key = 'library';

  /// Version du SCHÉMA de l'état local.
  ///
  /// ⚠ POURQUOI ELLE EXISTE. Une installation de six semaines survit à une
  /// réinstallation par-dessus — mesuré sur téléphone réel. Des usagers gardent
  /// donc des états anciens, et cette dette grandit toute seule : chaque jour
  /// ajoute des installations qui vieillissent.
  ///
  /// Sans numéro de version, le jour où un champ devient obligatoire, une
  /// entrée ancienne fait lever `fromJson` — et l'ancien `readAll` EFFAÇAIT
  /// alors TOUTE la bibliothèque. Une divergence de schéma détruisait le seul
  /// travail que le produit existe pour rendre possible.
  ///
  /// `1` = premier schéma numéroté. Les états écrits AVANT (une simple table
  /// `docId → document`, sans enveloppe) sont lus comme `0` et migrés.
  static const schemaVersion = 1;

  final MethodChannel _ch;

  /// Ce que la dernière lecture n'a pas su lire, s'il y a lieu. Diagnostic
  /// seulement : un écran peut le rapporter, rien ne s'en sert pour décider.
  String? dernierProbleme;

  /// Lit la bibliothèque. **Ne détruit JAMAIS rien.**
  ///
  /// ⚠ TOLÉRANTE PAR ENTRÉE. Une entrée illisible est écartée, les autres sont
  /// rendues. L'ancienne version enveloppait la boucle entière dans un seul
  /// `try` et purgeait la clé au premier échec : un document abîmé emportait
  /// toute l'étagère.
  ///
  /// ⚠ ET UNE VERSION INCONNUE NE DÉTRUIT PAS. Un état écrit par une version
  /// PLUS RÉCENTE (retour en arrière d'installation) est laissé INTACT : on rend
  /// ce qu'on sait lire, et on ne réécrit pas par-dessus. Effacer ce qu'on ne
  /// comprend pas est le geste qui coûte une bibliothèque entière.
  Future<Map<String, LocalDocument>> readAll() async {
    dernierProbleme = null;
    final raw = await _ch.invokeMethod<String>('get', {'name': _key});
    if (raw == null || raw.isEmpty) return {};

    Map<String, dynamic> table;
    int version;
    try {
      final decode = (jsonDecode(raw) as Map).cast<String, dynamic>();
      if (decode['v'] is int && decode['docs'] is Map) {
        version = decode['v'] as int;
        table = (decode['docs'] as Map).cast<String, dynamic>();
      } else {
        // Forme d'avant le numérotage : la table nue.
        version = 0;
        table = decode;
      }
    } catch (e) {
      // Contenu inexploitable : on le SIGNALE et on le laisse en place. Le
      // détruire ne rend pas l'étagère utilisable, et interdit tout examen.
      dernierProbleme = 'bibliothèque locale illisible (${e.runtimeType})';
      return {};
    }

    if (version > schemaVersion) {
      dernierProbleme =
          'bibliothèque écrite par une version plus récente (schéma $version) : '
          'laissée intacte';
      return {};
    }

    final docs = <String, LocalDocument>{};
    var ecartes = 0;
    for (final e in table.entries) {
      try {
        docs[e.key] = LocalDocument.fromJson((e.value as Map).cast<String, dynamic>());
      } catch (_) {
        ecartes++;
      }
    }
    if (ecartes > 0) {
      dernierProbleme = ecartes == 1
          ? "une entrée de la bibliothèque est illisible : écartée, les autres sont conservées"
          : "$ecartes entrées de la bibliothèque sont illisibles : écartées, les autres sont conservées";
    }

    // Migration vers le schéma courant : on ne réécrit QUE si on a tout lu.
    // Réécrire après avoir écarté une entrée la supprimerait pour de bon.
    if (version < schemaVersion && ecartes == 0 && docs.isNotEmpty) {
      await _writeAll(docs);
    }
    return docs;
  }

  Future<void> _writeAll(Map<String, LocalDocument> docs) async {
    await _ch.invokeMethod('put', {
      'name': _key,
      // ⚠ L'ENVELOPPE PORTE LA VERSION. Une lecture future saura donc si elle
      // comprend ce qu'elle lit, au lieu de le deviner à la forme.
      'value': jsonEncode({
        'v': schemaVersion,
        'docs': {for (final e in docs.entries) e.key: e.value.toJson()},
      }),
    });
  }

  Future<void> upsert(LocalDocument doc) async {
    final all = await readAll();
    all[doc.docId] = doc;
    await _writeAll(all);
  }

  Future<LocalDocument?> get(String docId) async => (await readAll())[docId];

  Future<void> remove(String docId) async {
    final all = await readAll();
    all.remove(docId);
    await _writeAll(all);
  }

  Future<void> clear() => _ch.invokeMethod('remove', {'name': _key}).then((_) {});
}
