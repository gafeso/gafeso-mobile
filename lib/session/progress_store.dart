import 'dart:convert';

import 'package:flutter/services.dart';

/// Où en est la lecture d'un document.
///
/// ⚠ **CETTE DONNÉE NE QUITTE JAMAIS L'APPAREIL.** Savoir qu'un lecteur en est
/// à la page 12 d'une thèse sur la santé maternelle est une information intime,
/// et le service — reprendre où l'on s'est arrêté — ne demande pas qu'un
/// serveur la connaisse. Elle est donc rangée dans le coffre chiffré local, au
/// même titre que les licences, et aucune requête ne la porte :
/// `test/progression_locale_test.dart` le tient, en inspectant ce qui part
/// réellement sur le réseau plutôt qu'en relisant le code.
class Progression {
  const Progression({
    required this.docId,
    required this.page,
    required this.pages,
    required this.majAt,
  });

  final String docId;

  /// Index de la page affichée, à partir de 0.
  final int page;

  /// Nombre total de pages du document.
  final int pages;

  /// Dernière mise à jour — sert à ordonner « Lectures en cours ».
  final DateTime majAt;

  /// Numéro affiché à l'usager : les pages se comptent à partir de 1.
  int get pageLisible => page + 1;

  /// Part lue, entre 0 et 1.
  ///
  /// ⚠ La page 1 d'un document de 10 pages n'est pas « 10 % lu » : c'est 0 %,
  /// on n'a rien lu encore. On compte les pages DERRIÈRE soi. Et la dernière
  /// page vaut 100 %, sans quoi aucun document ne serait jamais « terminé ».
  double get part {
    if (pages <= 1) return page >= pages - 1 ? 1 : 0;
    return (page / (pages - 1)).clamp(0, 1);
  }

  int get pourcent => (part * 100).round();

  /// Commencé mais pas fini. Un document jamais ouvert n'a pas d'entrée du tout.
  bool get enCours => !termine;

  /// ⚠ « Terminé » veut dire « arrivé à la dernière page », pas « tout lu ».
  /// On ne prétend pas savoir si quelqu'un a lu ce qu'il a affiché.
  bool get termine => pages > 0 && page >= pages - 1;

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'page': page,
        'pages': pages,
        'majAt': majAt.toIso8601String(),
      };

  static Progression fromJson(Map<String, dynamic> j) => Progression(
        docId: j['docId'] as String,
        page: (j['page'] as num).toInt(),
        pages: (j['pages'] as num).toInt(),
        majAt: DateTime.tryParse(j['majAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Coffre local des progressions.
///
/// Même forme que `LibraryStore` : enveloppe versionnée, lecture tolérante
/// entrée par entrée, et **jamais de purge** sur une entrée illisible — perdre
/// la position de lecture de tout un fonds parce qu'une ligne a mal vieilli
/// serait une punition disproportionnée.
class ProgressStore {
  ProgressStore({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('com.gafeso/secure');

  static const schemaVersion = 1;
  static const _cle = 'progression';

  final MethodChannel _ch;

  Future<Map<String, Progression>> readAll() async {
    final brut = await _ch.invokeMethod<String>('get', {'name': _cle});
    if (brut == null || brut.isEmpty) return {};
    try {
      final j = jsonDecode(brut);
      if (j is! Map) return {};
      final docs = j['docs'];
      if (docs is! Map) return {};
      final out = <String, Progression>{};
      for (final e in docs.entries) {
        try {
          out[e.key as String] = Progression.fromJson((e.value as Map).cast<String, dynamic>());
        } catch (_) {
          // Une entrée abîmée est SAUTÉE, pas une raison d'effacer les autres.
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> noter({required String docId, required int page, required int pages, DateTime? a}) async {
    if (pages <= 0 || page < 0) return; // rien à retenir d'un document vide
    final tout = await readAll();
    tout[docId] = Progression(
      docId: docId,
      page: page,
      pages: pages,
      majAt: a ?? DateTime.now(),
    );
    await _ecrire(tout);
  }

  Future<void> oublier(String docId) async {
    final tout = await readAll();
    if (tout.remove(docId) == null) return;
    await _ecrire(tout);
  }

  /// Appelée à la déconnexion et au changement d'école, avec la bibliothèque.
  Future<void> vider() => _ch.invokeMethod('remove', {'name': _cle});

  Future<void> _ecrire(Map<String, Progression> tout) => _ch.invokeMethod('put', {
        'name': _cle,
        'value': jsonEncode({
          'v': schemaVersion,
          'docs': {for (final e in tout.entries) e.key: e.value.toJson()},
        }),
      });
}
