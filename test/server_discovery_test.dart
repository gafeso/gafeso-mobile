import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/server_discovery.dart';
import 'package:gafeso_mobile/session/tenant_code.dart';

/// Découverte du serveur : l'URL n'est plus figée à la compilation.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ⚠ Le binding de test intercepte TOUT le HTTP et renvoie 400 : sans cette
    // remise à zéro, le serveur local n'est jamais joint et les assertions
    // passent pour de mauvaises raisons.
    HttpOverrides.global = null;
  });

  group('normalizeOrigin', () {
    test('complète le schéma manquant en https', () {
      expect(ServerDiscovery.normalizeOrigin('biblio.ecole.bf').toString(),
          'https://biblio.ecole.bf');
      expect(ServerDiscovery.normalizeOrigin('  biblio.ecole.bf/e/zinda ').toString(),
          'https://biblio.ecole.bf');
    });

    test('REFUSE le trafic en clair, avec un motif lisible', () {
      // La configuration réseau Android refuse déjà le clair en release :
      // l'accepter ici ne ferait que déplacer l'échec au premier appel, avec un
      // message incompréhensible.
      expect(
        () => ServerDiscovery.normalizeOrigin('http://biblio.ecole.bf'),
        throwsA(isA<ServerDiscoveryException>().having(
          (e) => e.message, 'message', contains('non chiffrée'))),
      );
    });

    test('refuse une saisie vide ou incompréhensible, sans exception brute', () {
      for (final v in ['', '   ', 'https://']) {
        expect(() => ServerDiscovery.normalizeOrigin(v),
            throwsA(isA<ServerDiscoveryException>()));
      }
    });

    test('conserve un port explicite', () {
      expect(ServerDiscovery.normalizeOrigin('https://biblio.ecole.bf:8443').toString(),
          'https://biblio.ecole.bf:8443');
    });
  });

  group('resolve — contre un serveur réel', () {
    late HttpServer server;
    late String origin;
    // Réponses pilotées par test.
    Map<String, dynamic>? descripteur;
    Map<String, dynamic>? sante;

    setUp(() async {
      descripteur = null;
      sante = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      origin = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        Map<String, dynamic>? corps;
        if (req.uri.path == '/.well-known/gafeso.json') corps = descripteur;
        if (req.uri.path == '/health' || req.uri.path == '/api/health') corps = sante;
        req.response.statusCode = corps == null ? 404 : 200;
        if (corps != null) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(corps));
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('lit le descripteur — CHARGE UTILE RÉELLE du serveur web', () async {
      // Ce corps est copié de la réponse observée sur l'application réelle
      // (GET /.well-known/gafeso.json), pas rédigé d'après une spécification.
      // Si le backend change la forme du document, ce test doit échouer.
      descripteur = {
        'version': 1,
        'api': 'http://api.localhost',
        'tenant': 'universite-joseph-ki-zer',
        'name': 'Université Joseph Ki-Zerbo',
        'enrollmentUrl': 'http://localhost:8080/e/universite-joseph-ki-zer',
      };
      final d = ServerDiscovery();
      addTearDown(d.close);

      final cfg = await d.resolve(origin);

      expect(cfg.apiUrl, 'http://api.localhost');
      expect(cfg.tenantSlug, 'universite-joseph-ki-zer');
      expect(cfg.schoolName, 'Université Joseph Ki-Zerbo');
      expect(cfg.displayHost, '127.0.0.1');
    });

    test('REPLI : sans descripteur, l’adresse peut être celle de l’API', () async {
      sante = {'status': 'ok', 'service': 'gafeso-api', 'timestamp': '2026-08-09T22:00:00Z'};
      final d = ServerDiscovery();
      addTearDown(d.close);

      final cfg = await d.resolve(origin);

      expect(cfg.apiUrl, origin);
      expect(cfg.tenantSlug, isNull);
    });

    test('refuse un serveur qui répond 200 sans être un Gafeso', () async {
      // N'importe quel site répond 200. Sans contrôle d'identité, l'application
      // se serait « connectée » puis aurait échoué plus tard sur un JSON
      // qu'elle ne sait pas lire.
      sante = {'status': 'ok', 'service': 'autre-chose'};
      final d = ServerDiscovery();
      addTearDown(d.close);

      await expectLater(
        d.resolve(origin),
        throwsA(isA<ServerDiscoveryException>().having(
          (e) => e.message, 'message', contains('Aucun serveur Gafeso'))),
      );
    });

    test('un descripteur SANS adresse d’API ne fait pas autorité', () async {
      // Le backend refuse de le produire, mais une façade mal configurée
      // pourrait le servir : une configuration creuse échouerait au premier
      // appel. On préfère tenter le repli.
      descripteur = {'version': 1, 'api': '', 'tenant': 'zinda'};
      sante = {'status': 'ok', 'service': 'gafeso-api'};
      final d = ServerDiscovery();
      addTearDown(d.close);

      final cfg = await d.resolve(origin);

      expect(cfg.apiUrl, origin, reason: 'le repli /health doit prendre le relais');
    });

    test('serveur injoignable : message utilisable, jamais d’exception brute', () async {
      await server.close(force: true);
      final d = ServerDiscovery(timeout: const Duration(milliseconds: 400));
      addTearDown(d.close);

      await expectLater(
        d.resolve(origin),
        throwsA(isA<ServerDiscoveryException>().having(
          (e) => e.message, 'message', contains('Vérifiez l’adresse'))),
      );
    });
  });

  test('le QR scanné donne l’origine à interroger', () {
    // Chaîne du parcours réel : QR imprimé → origine → descripteur.
    const scanne = 'https://biblio.ecole.bf/e/zinda';
    expect(TenantCode.parse(scanne), 'zinda');
    expect(TenantCode.origin(scanne).toString(), 'https://biblio.ecole.bf');
    expect(ServerDiscovery.normalizeOrigin(scanne).toString(), 'https://biblio.ecole.bf');
  });
}
