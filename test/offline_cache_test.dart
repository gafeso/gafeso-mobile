import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/cache/offline_cache.dart';

/// Socle « hors ligne par défaut ».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Le coffre chiffré passe par un canal natif, indisponible hors appareil :
  // on le simule par une carte en mémoire.
  final coffre = <String, String>{};
  int ecritures = 0;

  setUp(() {
    coffre.clear();
    ecritures = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
      final nom = (call.arguments as Map?)?['name'] as String?;
      switch (call.method) {
        case 'get':
          return coffre[nom];
        case 'put':
          ecritures++;
          coffre[nom!] = (call.arguments as Map)['value'] as String;
          return null;
        case 'remove':
          coffre.remove(nom);
          return null;
      }
      return null;
    });
  });

  OfflineCache cache() => OfflineCache();

  group('loadCached — la règle qui prime', () {
    test('succès réseau : la valeur est rendue ET mémorisée', () async {
      final t = DateTime.utc(2026, 8, 9, 10, 0);
      final r = await loadCached<List<String>>(
        cache: cache(),
        resource: 'prets',
        fromJson: (j) => (j as List).cast<String>(),
        toJson: (v) => v,
        fetch: () async => ['Droit constitutionnel'],
        clock: () => t,
      );

      expect(r.value, ['Droit constitutionnel']);
      expect(r.syncedAt, t);
      expect(r.lastError, isNull);
      expect(coffre.containsKey('cache:prets'), isTrue);
    });

    test('ÉCHEC RÉSEAU : le cache est CONSERVÉ, jamais effacé', () async {
      final t0 = DateTime.utc(2026, 8, 9, 10, 0);
      await loadCached<List<String>>(
        cache: cache(), resource: 'prets',
        fromJson: (j) => (j as List).cast<String>(), toJson: (v) => v,
        fetch: () async => ['Anatomie générale'], clock: () => t0,
      );
      final avant = ecritures;

      final r = await loadCached<List<String>>(
        cache: cache(), resource: 'prets',
        fromJson: (j) => (j as List).cast<String>(), toJson: (v) => v,
        fetch: () async => throw Exception('SocketException: réseau coupé'),
        clock: () => t0.add(const Duration(hours: 2)),
      );

      expect(r.value, ['Anatomie générale'],
          reason: 'une panne réseau ne doit jamais faire disparaître les prêts');
      expect(r.syncedAt, t0, reason: 'la date reste celle de la VRAIE synchro');
      expect(r.lastError, contains('Pas de réseau'));
      expect(ecritures, avant, reason: 'aucune écriture : le cache n’est pas touché');
    });

    test('l’erreur s’AJOUTE à la valeur, elle ne la remplace pas', () async {
      final t0 = DateTime.utc(2026, 8, 9, 10, 0);
      await loadCached<int>(
        cache: cache(), resource: 'n', fromJson: (j) => j as int, toJson: (v) => v,
        fetch: () async => 3, clock: () => t0,
      );
      final r = await loadCached<int>(
        cache: cache(), resource: 'n', fromJson: (j) => j as int, toJson: (v) => v,
        fetch: () async => throw Exception('boom'), clock: () => t0,
      );
      expect(r.hasValue, isTrue);
      expect(r.lastError, isNotNull);
    });

    test('jamais synchronisé + échec : pas de valeur, mais un motif', () async {
      final r = await loadCached<int>(
        cache: cache(), resource: 'vide', fromJson: (j) => j as int, toJson: (v) => v,
        fetch: () async => throw Exception('SocketException'),
      );
      expect(r.hasValue, isFalse);
      expect(r.lastError, isNotNull);
      expect(r.freshnessAt(DateTime.utc(2026)), Freshness.never);
    });

    test('un instantané ILLISIBLE est traité comme absent, sans propager', () async {
      coffre['cache:prets'] = '{ ceci n est pas du json';
      final r = await loadCached<int>(
        cache: cache(), resource: 'prets', fromJson: (j) => j as int, toJson: (v) => v,
        fetch: () async => throw Exception('hors ligne'),
      );
      // Un cache corrompu ne doit pas faire échouer l'ouverture d'un écran :
      // c'est l'inverse exact de ce à quoi il sert.
      expect(r.hasValue, isFalse);
      expect(r.lastError, isNotNull);
    });
  });

  group('fraîcheur', () {
    final t = DateTime.utc(2026, 8, 9, 12, 0);

    test('trois états, et pas deux', () {
      expect(const Cached<int>().freshnessAt(t), Freshness.never);
      expect(Cached<int>(value: 1, syncedAt: t).freshnessAt(t), Freshness.fresh);
      expect(
        Cached<int>(value: 1, syncedAt: t.subtract(const Duration(hours: 9))).freshnessAt(t),
        Freshness.stale,
      );
    });

    test('VOLATILITÉ : le seuil dépend de la ressource, pas d’un réglage global', () {
      final ilYA3h = Cached<int>(value: 1, syncedAt: t.subtract(const Duration(hours: 3)));
      final ilYA9h = Cached<int>(value: 1, syncedAt: t.subtract(const Duration(hours: 9)));

      // Prêts : ils ne changent que quelques fois par mois. À 15 minutes, un
      // étudiant hors réseau — l'utilisateur type — verrait le bandeau en
      // permanence, et un avertissement permanent n'avertit plus.
      expect(ilYA3h.freshnessAt(t, maxAge: Volatility.emprunts), Freshness.fresh);
      expect(ilYA9h.freshnessAt(t, maxAge: Volatility.emprunts), Freshness.stale);
    });

    test('CARTE : jamais datée, quelle que soit l’ancienneté', () {
      // Le code-barres est immuable. Afficher « daté » ferait douter le
      // bibliothécaire au comptoir — et douter d'un code-barres, c'est refuser
      // un prêt.
      final vieille = Cached<int>(value: 1, syncedAt: t.subtract(const Duration(days: 90)));
      expect(vieille.freshnessAt(t, maxAge: Volatility.carte), Freshness.fresh);
      // Jamais synchronisée reste jamais synchronisée : il n'y a rien à montrer.
      expect(const Cached<int>().freshnessAt(t, maxAge: Volatility.carte), Freshness.never);
    });

    test('libellés lisibles au comptoir', () {
      expect(freshnessLabel(null, t), 'Jamais synchronisé');
      expect(freshnessLabel(t.subtract(const Duration(seconds: 20)), t),
          'Synchronisé à l’instant');
      expect(freshnessLabel(t.subtract(const Duration(minutes: 5)), t),
          'Synchronisé il y a 5 min');
      expect(freshnessLabel(t.subtract(const Duration(hours: 3)), t),
          'Synchronisé il y a 3 h');
      expect(freshnessLabel(t.subtract(const Duration(days: 1)), t), 'Synchronisé hier');
      expect(freshnessLabel(t.subtract(const Duration(days: 4)), t),
          'Synchronisé il y a 4 jours');
    });

    test('horloge reculée : on n’invente pas une durée négative', () {
      // L'appareil peut avoir reculé entre deux lancements. « il y a -3 h »
      // n'apprendrait rien et ferait douter de tout l'écran.
      expect(freshnessLabel(t.add(const Duration(hours: 3)), t),
          'Synchronisé (date incertaine)');
    });
  });
}
