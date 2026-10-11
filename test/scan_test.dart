import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/api/scan.dart';

/// ⚠ **QUATRE ISSUES, PAS DEUX.**
///
/// « Introuvable » recouvrirait trois situations qui appellent trois gestes
/// différents : changer d'établissement, scanner le bon code, ou attendre
/// d'avoir du réseau. Les confondre renvoie chercher au mauvais endroit — et
/// c'est exactement ce qui arriverait si le client découpait l'adresse
/// lui-même au lieu de la soumettre au serveur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  late HttpServer serveur;
  late int statut;
  late String corps;
  late List<String> recues;

  setUp(() async {
    statut = 200;
    corps = '{"id":"f197f1b9-919d-413c-9e7f-534cadd4e2cf","title":"Droit foncier"}';
    recues = [];
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((r) async {
      recues.add(r.uri.toString());
      // ⚠ LE CORPS DE LA REQUÊTE DOIT ÊTRE DRAINÉ, MÊME VIDE. Sans cela, une
      // réponse d'erreur reste en suspens trente secondes : le client a envoyé
      // un en-tête `Content-Type` sur un GET, attend que la requête soit
      // consommée, et le test « échoue » en hors-ligne au lieu de lire le 409.
      // Trente secondes de latence sont le symptôme à reconnaître.
      await r.drain<void>();
      final octets = utf8.encode(corps);
      r.response.statusCode = statut;
      r.response.headers
        ..set('content-type', 'application/json')
        ..contentLength = octets.length;
      r.response.add(octets);
      await r.response.close();
    });
  });

  tearDown(() async => serveur.close(force: true));

  GafesoApi client() => GafesoApi(
        baseUrl: 'http://${serveur.address.host}:${serveur.port}',
        tenantSlug: 'zinda',
        token: 'jeton',
      );

  Future<ResultatScan> scanner(String url, {bool local = false}) async {
    final api = client();
    addTearDown(api.close);
    return reconnaitreAdresse(api, url, dejaSurLAppareil: (_) => local);
  }

  group('les trois réponses du serveur', () {
    test('200 → la notice', () async {
      // Charge RÉELLE relevée le 11/10/2026 sur l'instance de dev.
      expect(await scanner('http://localhost:3000/opac/abc'), isA<ScanNotice>());
    });

    test('⚠ 409 → le livre existe AILLEURS, et on le dit', () async {
      statut = 409;
      corps = jsonEncode({
        'message': 'Ce document appartient à une autre bibliothèque '
            '(bib.autre-ecole.bf). Changez d’établissement dans l’application '
            'pour l’ouvrir.',
        'statusCode': 409,
      });
      final r = await scanner('https://bib.autre-ecole.bf/opac/abc');
      expect(r, isA<ScanAutreEtablissement>());
      final a = r as ScanAutreEtablissement;
      // La phrase vient du SERVEUR : lui seul sait quels domaines sont les
      // siens, et il a déjà rédigé le refus.
      expect(a.message, contains('autre bibliothèque'));
      expect(a.message, contains('bib.autre-ecole.bf'));
      // ⚠ Et c'est l'ADRESSE SCANNÉE qu'on rouvrira, pas un hôte redécoupé du
      // message : lire une adresse dans une phrase destinée à un humain, c'est
      // se lier à sa formulation.
      expect(a.adresse, 'https://bib.autre-ecole.bf/opac/abc');
    });

    test('404 → ce n’est pas un QR Gafeso', () async {
      statut = 404;
      corps = jsonEncode({
        'message': 'Cette adresse n’est pas celle d’une notice Gafeso.',
        'statusCode': 404,
      });
      final r = await scanner('pas-une-url');
      expect(r, isA<ScanInconnue>());
      expect((r as ScanInconnue).message, contains('notice Gafeso'));
    });
  });

  group('⚠ c’est le SERVEUR qui décide, pas le client', () {
    test('l’adresse entière lui est soumise, telle quelle', () async {
      await scanner('https://bib.autre-ecole.bf/opac/abc');
      expect(recues.single, contains('/opac/scan'));
      expect(Uri.parse(recues.single).queryParameters['url'],
          'https://bib.autre-ecole.bf/opac/abc');
    });

    test('⚠ TÉMOIN — le client n’appelle PAS /opac/records de son côté', () async {
      // C'est le défaut que la route existe pour empêcher : un client qui
      // découperait l'URL appellerait SA propre école et dirait « introuvable »
      // alors que le livre existe, ailleurs.
      await scanner('https://bib.autre-ecole.bf/opac/f197f1b9-919d-413c-9e7f-534cadd4e2cf');
      expect(recues.where((u) => u.contains('/opac/records')), isEmpty);
    });
  });

  group('⚠ HORS LIGNE — devant le rayonnage, sans data', () {
    // ⚠ UN PORT MORT, pas un serveur refermé : fermer celui du test laisse la
    // connexion aboutir par intermittence, et le cas devient capricieux. On
    // vise 127.0.0.1:1, où rien n'écoute jamais.
    Future<ResultatScan> horsLigne({required bool local}) async {
      final api = GafesoApi(baseUrl: 'http://127.0.0.1:1', tenantSlug: 'zinda');
      addTearDown(api.close);
      return reconnaitreAdresse(
        api,
        'http://localhost:3000/opac/f197f1b9-919d-413c-9e7f-534cadd4e2cf',
        dejaSurLAppareil: (_) => local,
      );
    }

    test('le document est DÉJÀ sur l’appareil : on l’ouvre', () async {
      final r = await horsLigne(local: true);
      expect(r, isA<ScanDejaLa>());
      expect((r as ScanDejaLa).docId, 'f197f1b9-919d-413c-9e7f-534cadd4e2cf');
    });

    test('il n’y est pas : on le DIT, on ne prétend pas qu’il n’existe pas',
        () async {
      expect(await horsLigne(local: false), isA<ScanHorsLigne>());
    });
  });

  group('⚠ le découpage d’appoint ne reconnaît QU’un identifiant', () {
    test('un UUID en fin de chemin est reconnu', () {
      expect(
        identifiantDansAdresse('https://bib.uo.bf/opac/f197f1b9-919d-413c-9e7f-534cadd4e2cf'),
        'f197f1b9-919d-413c-9e7f-534cadd4e2cf',
      );
    });

    test('⚠ un segment QUELCONQUE est refusé', () {
      // Sans cette exigence, le premier QR venu ferait ouvrir n'importe quoi.
      for (final mauvais in [
        'https://exemple.org/opac/connexion',
        'https://exemple.org/',
        'https://exemple.org/opac/12345',
        'pas-une-url-du-tout',
        '',
      ]) {
        expect(identifiantDansAdresse(mauvais), isNull, reason: mauvais);
      }
    });
  });
}
