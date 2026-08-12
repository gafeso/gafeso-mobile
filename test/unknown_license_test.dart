import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/api/offline_service.dart';
import 'package:gafeso_mobile/session/library_store.dart';

/// Une licence que le SERVEUR NE CONNAÎT PAS ne doit jamais faire disparaître
/// un document déjà téléchargé.
///
/// Le serveur répondait `revoked` pour un identifiant inconnu, et l'appareil
/// purgeait tout ce qui n'était pas `active`. Une restauration de sauvegarde
/// antérieure à l'émission suffisait donc à détruire l'ouvrage d'un étudiant,
/// avec le message « n'est plus accessible » — qui était faux.
void main() {
  late HttpServer server;
  late String statutRendu;

  // LibraryStore passe par un canal de plateforme (stockage sécurisé) :
  // indisponible hors appareil, on le simule par une carte en mémoire.
  final stockage = <String, String>{};

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ⚠ Le binding de test intercepte TOUT le HTTP et renvoie 400 : sans cette
    // remise à zéro, le serveur local n'est jamais joint et les assertions
    // passent (ou échouent) pour de mauvaises raisons — le cas « revoked »
    // semblait vert alors qu'aucune requête n'était partie.
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
      final nom = (call.arguments as Map?)?['name'] as String?;
      switch (call.method) {
        case 'get':
          return stockage[nom];
        case 'put':
          stockage[nom!] = (call.arguments as Map)['value'] as String;
          return null;
        case 'remove':
          stockage.remove(nom);
          return null;
        default:
          return null;
      }
    });

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode([
          {'id': 'lic-1', 'status': statutRendu, 'expiresAt': null},
        ]));
      await req.response.close();
    });
  });

  tearDownAll(() async => server.close(force: true));

  Future<OfflineService> service() async {
    stockage.clear();
    final dir = await Directory.systemTemp.createTemp('gafeso-unknown-');
    addTearDown(() => dir.delete(recursive: true).catchError((_) => dir));
    final api = GafesoApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      tenantSlug: 'zinda',
      token: 'jeton',
    );
    addTearDown(api.close);
    final svc = OfflineService(api: api, storageDir: dir);
    final blob = File('${dir.path}/doc-1.gafs')..writeAsBytesSync([1, 2, 3]);
    await svc.library.upsert(
      LocalDocument(
        docId: 'doc-1',
        title: 'Précis de médecine',
        licenseId: 'lic-1',
        licenseBody: '{}',
        signature: 'sig',
        licensePublicKey: 'pub',
        wrappedCek: 'cek',
        blobPath: blob.path,
      ),
    );
    return svc;
  }

  test('statut « unknown » : le document est CONSERVÉ', () async {
    statutRendu = 'unknown';
    final svc = await service();

    final res = await svc.refreshAll();

    expect(res['doc-1'], 'unknown');
    final reste = await svc.library.get('doc-1');
    expect(reste, isNotNull,
        reason: 'inconnu du serveur ≠ révoqué : rien ne justifie de détruire');
  });

  test('statut « revoked » : le document est bien purgé', () async {
    statutRendu = 'revoked';
    final svc = await service();

    await svc.refreshAll();

    expect(await svc.library.get('doc-1'), isNull,
        reason: 'une révocation RÉELLE doit toujours purger');
  });
}
