import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/screens/reader_screen.dart';
import 'package:gafeso_mobile/session/progress_store.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';

/// ⚠ **LA PROGRESSION DE LECTURE NE QUITTE PAS L'APPAREIL.**
///
/// Savoir qu'un lecteur en est à la page 12 d'une thèse sur la santé maternelle
/// est une information intime. Le service rendu — reprendre où l'on s'est
/// arrêté — ne demande à aucun moment qu'un serveur la connaisse.
///
/// ⚠ ET CE TEST LE MESURE SUR LE FIL, pas en relisant le code. Un vrai serveur
/// HTTP est monté, l'app y est branchée, on lui fait tourner des pages, et on
/// regarde ce qui est arrivé. Un test qui se contenterait de chercher un appel
/// dans les sources laisserait passer le jour où la progression part en
/// passager d'une autre requête.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer serveur;
  late List<String> recues;
  late List<String> corps;
  late Map<String, String> coffre;

  // ⚠ SANS CETTE LIGNE, LA MESURE NE MESURE RIEN.
  //
  // `flutter_test` installe par défaut un `HttpClient` factice qui répond 400 à
  // TOUTE requête, pour qu'aucun test ne parte sur le réseau. Mon premier jet
  // s'en est trouvé « vert » sur le cas principal — aucune requête reçue —
  // alors qu'aucune requête n'aurait PU être reçue, quoi que fasse le code.
  // C'est le témoin positif qui l'a révélé : lui exigeait une requête, et ne
  // l'a jamais vue arriver.
  //
  // On rend donc le vrai client, et le serveur d'essai écoute pour de bon sur
  // la boucle locale.
  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    recues = [];
    corps = [];
    coffre = {};
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((r) async {
      recues.add('${r.method} ${r.uri.path}');
      try {
        corps.add(await utf8.decoder.bind(r).join());
      } catch (e) {
        corps.add('<corps illisible: $e>');
      }
      r.response.statusCode = 200;
      r.response.headers.set('content-type', 'application/json');
      r.response.write('[]');
      await r.response.close();
    }, onError: (Object e) => recues.add('<erreur serveur: $e>'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (c) async {
      final nom = (c.arguments as Map?)?['name'] as String?;
      switch (c.method) {
        case 'get':
          return coffre[nom];
        case 'put':
          coffre[nom!] = (c.arguments as Map)['value'] as String;
          return true;
        case 'remove':
          coffre.remove(nom);
          return true;
      }
      return null;
    });
  });

  tearDown(() async => serveur.close(force: true));

  /// Le canal du lecteur, simulé : c'est par lui que le natif annonce sa page.
  const canal = MethodChannel('com.gafeso/reader-test');

  Future<void> tournerLesPages(WidgetTester t, ProgressStore store) async {
    await t.pumpWidget(MaterialApp(
      theme: gafesoClair(),
      home: ReaderScreen(
        title: 'Une thèse',
        params: const {},
        docId: 'doc-1',
        progression: store,
        channel: canal,
        vueNative: const SizedBox(key: Key('page')),
      ),
    ));
    await t.pump();

    // Le natif annonce les pages, comme il le fait sur l'appareil.
    for (final p in [0, 1, 2, 7, 11]) {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        canal.name,
        canal.codec.encodeMethodCall(
          MethodCall('page', {'index': p, 'total': 12}),
        ),
        (_) {},
      );
      await t.pump();
    }
    await t.pumpAndSettle();
  }

  testWidgets('⚠ AUCUNE requête ne part pendant que les pages défilent', (t) async {
    final store = ProgressStore();
    // Un client RÉEL, branché sur un serveur RÉEL : si quoi que ce soit partait,
    // il arriverait ici.
    final api = GafesoApi(
      baseUrl: 'http://${serveur.address.host}:${serveur.port}',
      tenantSlug: 'zinda',
      token: 'jeton',
    );
    addTearDown(api.close);

    await tournerLesPages(t, store);

    expect(recues, isEmpty, reason: 'le serveur a reçu : $recues');
    expect(corps.join(), isNot(contains('page')));
  });

  testWidgets('…et pourtant la progression EST retenue, sur l’appareil', (t) async {
    // Témoin positif : sans lui, « aucune requête » serait aussi vrai d'un
    // écran qui ne fait rien du tout.
    final store = ProgressStore();
    await tournerLesPages(t, store);

    final tout = await store.readAll();
    expect(tout['doc-1'], isNotNull);
    expect(tout['doc-1']!.page, 11);
    expect(tout['doc-1']!.pages, 12);
    expect(tout['doc-1']!.termine, isTrue);
    // Elle est bien dans le COFFRE, pas dans un fichier en clair.
    expect(coffre.keys, contains('progression'));
  });

  // ⚠ UN `test`, PAS UN `testWidgets`, ET C'EST LA SECONDE CHOSE QUE CE TÉMOIN
  // A APPRISE. `testWidgets` s'exécute en temps SIMULÉ : une vraie requête
  // réseau n'y aboutit jamais, elle reste pendue. Le témoin en `testWidgets`
  // ne « échouait » donc pas, il ne finissait pas — et un test qui ne finit pas
  // est encore plus facile à ignorer qu'un test rouge.
  test('⚠ TÉMOIN — le serveur d’essai enregistre bien ce qui lui arrive', () async {
    // Sans ce cas, « aucune requête reçue » pourrait venir d'un serveur muet ou
    // d'un client neutralisé, et le premier test applaudirait une mesure qui ne
    // mesure rien. C'est précisément ce qui s'est produit : `flutter_test`
    // installe un client factice qui répond 400 à tout, et c'est ce témoin —
    // lui seul — qui l'a révélé.
    final api = GafesoApi(
      baseUrl: 'http://${serveur.address.host}:${serveur.port}',
      tenantSlug: 'zinda',
      token: 'jeton',
    );
    addTearDown(api.close);
    await api.myDocuments();
    expect(recues, ['GET /offline/my-documents']);
  });

  group('ce que la progression dit, et ce qu’elle refuse de dire', () {
    test('⚠ la page 1 sur 10 n’est pas « 10 % lu » : on n’a rien lu encore', () {
      final p = Progression(docId: 'd', page: 0, pages: 10, majAt: DateTime(2026));
      expect(p.pourcent, 0);
      expect(p.termine, isFalse);
    });

    test('la dernière page vaut 100 %, sinon rien n’est jamais terminé', () {
      final p = Progression(docId: 'd', page: 9, pages: 10, majAt: DateTime(2026));
      expect(p.pourcent, 100);
      expect(p.termine, isTrue);
    });

    test('un document d’une seule page est terminé dès qu’on l’ouvre', () {
      final p = Progression(docId: 'd', page: 0, pages: 1, majAt: DateTime(2026));
      expect(p.termine, isTrue);
    });
  });

  group('le coffre ne punit pas', () {
    test('⚠ une entrée abîmée est SAUTÉE, les autres survivent', () async {
      coffre['progression'] =
          '{"v":1,"docs":{"bon":{"docId":"bon","page":2,"pages":9,"majAt":"2026-10-09T10:00:00Z"},'
          '"casse":{"docId":"casse"}}}';
      final tout = await ProgressStore().readAll();
      expect(tout.keys, ['bon']);
      expect(tout['bon']!.page, 2);
    });

    test('un coffre illisible rend vide, il n’efface rien', () async {
      coffre['progression'] = 'ceci n’est pas du JSON';
      expect(await ProgressStore().readAll(), isEmpty);
      expect(coffre['progression'], isNotNull);
    });
  });
}
