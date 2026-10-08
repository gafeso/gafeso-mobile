import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/gafeso_api.dart';

/// Socle « hors ligne par défaut » : chaque écran s'affiche depuis la dernière
/// synchronisation, avec un indicateur de fraîcheur.
///
/// ── Pourquoi c'est la forme de la couche de données, pas une finition ─────
/// Le cas d'usage réel est le comptoir d'une bibliothèque sans wifi. Un écran
/// qui attend le réseau pour s'afficher y est inutilisable ; un écran qui
/// échoue avec une exception l'est encore plus. On inverse donc la charge :
/// **on affiche toujours ce qu'on sait**, en disant DE QUAND ça date, et le
/// réseau ne fait que rafraîchir.
///
/// ── La règle qui prime sur tout ───────────────────────────────────────────
/// **Un échec réseau n'efface JAMAIS le cache.** C'est la même règle que
/// `unknown` côté licences : ne pas savoir n'est pas savoir que non. Une panne
/// de réseau qui viderait la liste des prêts afficherait « aucun prêt » à un
/// étudiant qui en a trois — un mensonge, au moment précis où il ne peut pas
/// le vérifier.
///
/// Seule une réponse SERVEUR fait autorité pour remplacer un contenu.

/// VOLATILITÉ : à quelle vitesse une donnée peut devenir FAUSSE.
///
/// Le critère n'est pas « depuis quand l'ai-je », mais « depuis quand
/// pourrait-elle mentir ». La distinction change tout : un seuil unique et
/// court ferait apparaître le bandeau en PERMANENCE chez un étudiant hors
/// réseau — l'utilisateur type — et il deviendrait le décor qu'on cherchait
/// justement à éviter. Un avertissement permanent n'avertit plus.
///
/// Ce n'est donc pas un réglage fin : ces données n'ont pas la même nature.
abstract final class Volatility {
  /// Prêts et réservations : ils ne changent que quelques fois par mois, et
  /// les échéances se calculent localement à partir de dates déjà présentes.
  static const emprunts = Duration(hours: 6);

  /// Carte de lecteur : le code-barres est IMMUABLE. Afficher « daté » ferait
  /// douter le bibliothécaire au comptoir sans aucune raison — et douter d'un
  /// code-barres, c'est refuser un prêt.
  static const Duration? carte = null;

  /// Défaut prudent pour une ressource dont on n'a pas tranché la volatilité.
  static const defaut = Duration(hours: 6);
}

/// Fraîcheur d'une donnée affichée.
enum Freshness {
  /// Synchronisée à l'instant (ou presque) : rien à signaler.
  fresh,

  /// Affichée depuis le cache — la date de synchronisation doit être visible.
  stale,

  /// Jamais synchronisée : il n'y a rien à montrer, et il faut le dire
  /// autrement qu'avec un écran blanc.
  never,
}

/// Valeur issue du cache, avec sa date de synchronisation.
@immutable
class Cached<T> {
  const Cached({this.value, this.syncedAt, this.lastError});

  final T? value;
  final DateTime? syncedAt;

  /// Dernier échec de rafraîchissement, s'il y en a eu un. Présent EN PLUS de
  /// la valeur : on montre les données connues ET on signale qu'elles n'ont pas
  /// pu être mises à jour. L'un n'annule pas l'autre.
  final String? lastError;

  bool get hasValue => value != null;

  /// Fraîcheur, jugée selon la VOLATILITÉ de la ressource (voir `Volatility`).
  ///
  /// `maxAge` à `null` signifie « ne vieillit pas » : la donnée n'est jamais
  /// présentée comme datée.
  Freshness freshnessAt(DateTime now, {Duration? maxAge = Volatility.defaut}) {
    if (syncedAt == null || value == null) return Freshness.never;
    if (maxAge == null) return Freshness.fresh;
    return now.difference(syncedAt!) <= maxAge ? Freshness.fresh : Freshness.stale;
  }

  Cached<T> withError(String message) =>
      Cached<T>(value: value, syncedAt: syncedAt, lastError: message);
}

/// Libellé de fraîcheur destiné à l'écran.
///
/// Volontairement en langage courant plutôt qu'en horodatage : « il y a 5 min »
/// se lit d'un coup d'œil, « 2026-08-09T22:14:03Z » demande un calcul mental
/// que personne ne fait au comptoir.
String freshnessLabel(DateTime? syncedAt, DateTime now) {
  if (syncedAt == null) return 'Jamais synchronisé';
  final d = now.difference(syncedAt);
  if (d.isNegative) {
    // Horloge reculée entre deux lancements : on ne prétend pas savoir.
    return 'Synchronisé (date incertaine)';
  }
  if (d.inSeconds < 60) return 'Synchronisé à l’instant';
  if (d.inMinutes < 60) return 'Synchronisé il y a ${d.inMinutes} min';
  if (d.inHours < 24) {
    return 'Synchronisé il y a ${d.inHours} h';
  }
  if (d.inDays == 1) return 'Synchronisé hier';
  return 'Synchronisé il y a ${d.inDays} jours';
}

/// Stockage des instantanés.
///
/// Passe par le coffre chiffré du keystore (canal `com.gafeso/secure`), comme
/// la session — et non par un fichier en clair. Ces instantanés contiennent des
/// données personnelles : titres empruntés, échéances, identité du lecteur. Les
/// écrire en clair dans le répertoire de l'application les exposerait à toute
/// sauvegarde ou extraction, alors même que le produit chiffre les documents
/// eux-mêmes. Ce serait incohérent.
class OfflineCache {
  OfflineCache({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('com.gafeso/secure');

  final MethodChannel _ch;

  String _key(String resource) => 'cache:$resource';

  Future<Cached<T>> read<T>(
    String resource,
    T Function(Object json) fromJson,
  ) async {
    try {
      final raw = await _ch.invokeMethod<String>('get', {'name': _key(resource)});
      if (raw == null || raw.isEmpty) return Cached<T>();
      final env = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.tryParse(env['syncedAt'] as String? ?? '');
      return Cached<T>(value: fromJson(env['value'] as Object), syncedAt: at);
    } catch (_) {
      // Instantané illisible (format changé, écriture interrompue) : on le
      // traite comme absent. Propager l'erreur ferait échouer l'ouverture d'un
      // écran à cause d'un CACHE — l'inverse exact de ce qu'il sert à faire.
      return Cached<T>();
    }
  }

  Future<void> write(String resource, Object value, DateTime syncedAt) async {
    await _ch.invokeMethod('put', {
      'name': _key(resource),
      'value': jsonEncode({'syncedAt': syncedAt.toIso8601String(), 'value': value}),
    });
  }

  Future<void> clear(String resource) async {
    await _ch.invokeMethod('remove', {'name': _key(resource)});
  }
}

/// Charge une ressource : le cache d'abord, le réseau ensuite.
///
/// Rend TOUJOURS quelque chose d'affichable. En cas d'échec réseau, la valeur
/// en cache est conservée et l'erreur est jointe — jamais substituée.
Future<Cached<T>> loadCached<T>({
  required OfflineCache cache,
  required String resource,
  required T Function(Object json) fromJson,
  required Object Function(T value) toJson,
  required Future<T> Function() fetch,
  DateTime Function()? clock,
}) async {
  final maintenant = (clock ?? DateTime.now)();
  final enCache = await cache.read<T>(resource, fromJson);
  try {
    final frais = await fetch();
    await cache.write(resource, toJson(frais), maintenant);
    return Cached<T>(value: frais, syncedAt: maintenant);
  } catch (e) {
    // ⚠ UN MODULE ABSENT N'EST PAS UNE PANNE, ET NE S'AFFICHE PAS COMME TELLE.
    // Quand le serveur refuse en disant que la circulation n'est pas en
    // service, l'écran concerné est en train de disparaître du menu : y coller
    // « Mise à jour impossible » ferait clignoter une erreur pour annoncer un
    // service qui n'existe pas ici. On rend le cache tel quel, sans erreur.
    if (e is GafesoApiException && e.circulationInactive) return enCache;
    // ON NE TOUCHE PAS AU CACHE. Voir l'en-tête : ne pas savoir n'est pas
    // savoir que non.
    return enCache.withError(_message(e));
  }
}

String _message(Object e) {
  final t = e.toString();
  if (t.contains('SocketException') ||
      t.contains('Connection') ||
      t.contains('TimeoutException')) {
    return 'Pas de réseau — données de la dernière synchronisation.';
  }
  return 'Mise à jour impossible — données de la dernière synchronisation.';
}
