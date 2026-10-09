/// E2E de l'Étape 2 (client HTTP) — **SANS TÉLÉPHONE**, contre le vrai backend.
///
/// Gaté par `MOBILE_E2E=1` : exige le dépôt backend (`GAFESO_BACKEND_DIR`, défaut
/// `~/bibliocloud`) avec son infra dev up (Postgres 5433 + MinIO 9000), plus la toolchain
/// JVM/Kotlin pour la crypto appareil.
///
///   MOBILE_E2E=1 flutter test test/offline_step2_e2e_test.dart
///
/// Ce que ce test prouve (et ce qu'il ne prouve pas) :
///  - ✅ le client Dart `GafesoApi` parle correctement au backend réel : enregistrement d'un
///    appareil avec une **clé publique EC P-256**, émission de licence (droit vérifié côté
///    serveur), URL signée du blob, téléchargement, statut, re-check après révocation ;
///  - ✅ la licence émise est **exploitable par le code appareil** : signature Ed25519 vérifiée
///    et CEK déballée en **EC-KEM** par le *vrai* code Kotlin (harnais JVM), qui déchiffre
///    ensuite le blob jusqu'à `%PDF` ;
/// ⚠ **PLUS AUCUN JETON FABRIQUÉ.** Ce test se connectait avec le jeton que la
/// fixture backend imprimait, signé avec `JWT_SECRET` — un jeton qu'aucun
/// usager n'obtiendrait jamais, et une porte de fabrication de session ouverte
/// dans un script de développement. Il passe désormais par `POST /auth/login`
/// avec les comptes de recette (`recette-etu@` pour lire, `recette-bib@` pour
/// révoquer), exactement comme l'application et comme le comptoir. Le backend
/// peut retirer l'impression du jeton.
///
/// Conséquence heureuse : le document éprouvé est celui que le script de
/// recette a préparé par les routes du produit, et non une notice écrite
/// directement en base.
///
///  - ❌ il ne prouve PAS l'**Android Keystore** (`PURPOSE_AGREE_KEY` sur SoC réel) : la clé
///    d'appareil est ici un fichier openssl, pas le keystore. C'est le résiduel on-device
///    assumé par l'amendement, à plier en session device.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';

final _run = Platform.environment['MOBILE_E2E'] == '1';
final _backendDir = Platform.environment['GAFESO_BACKEND_DIR'] ??
    '${Platform.environment['HOME']}/bibliocloud';
final _home = Platform.environment['HOME']!;
final _java = '$_home/mobiletools/jdk/bin/java';
final _kotlinLib = '$_home/mobiletools/gradle-8.9/lib';
final _xvec = '$_home/mobiletools/xvec';

/// Mot de passe des comptes de recette, lu dans le `.env` du backend.
///
/// ⚠ Il n'est ni affiché, ni journalisé, ni écrit ailleurs : un secret qu'un
/// test imprime finit dans une sortie de CI que personne ne relit.
String _recettePassword() {
  final f = File('$_backendDir/.env');
  if (!f.existsSync()) throw StateError('.env backend introuvable : ${f.path}');
  for (final l in f.readAsLinesSync()) {
    if (l.startsWith('RECETTE_PASSWORD=')) {
      return l.substring('RECETTE_PASSWORD='.length).trim();
    }
  }
  throw StateError('RECETTE_PASSWORD absent du .env backend — '
      'lancer `npm run comptes:recette` dans le dépôt backend');
}

// ⚠ `_backendScript` A DISPARU, ET C'EST LE POINT. Ce test n'appelle plus
// AUCUN script du backend : il se connecte, lit l'étagère que le script de
// recette a garnie par les routes du produit, et révoque par la route du
// produit. Plus de jeton fabriqué, plus d'écriture directe en base.


/// Démarre l'API Nest (harness du backend) et renvoie son port.
Future<(Process, int)> _startApi() async {
  final proc = await Process.start(
    'npx',
    [
      'dotenv', '-e', '../../.env', '--',
      'npx', 'ts-node', '--transpile-only',
      '--compiler-options', '{"module":"commonjs"}',
      'src/offline-licensing/offline-licensing.e2e.harness.ts',
    ],
    workingDirectory: '$_backendDir/apps/api',
    environment: {...Platform.environment, 'TS_NODE_TRANSPILE_ONLY': '1'},
  );
  final port = Completer<int>();
  final err = StringBuffer();
  proc.stdout.transform(utf8.decoder).listen((s) {
    final m = RegExp(r'E2E_LISTENING (\d+)').firstMatch(s);
    if (m != null && !port.isCompleted) port.complete(int.parse(m.group(1)!));
  });
  proc.stderr.transform(utf8.decoder).listen(err.write);
  final p = await port.future.timeout(
    const Duration(seconds: 90),
    onTimeout: () => throw StateError('API non démarrée : $err'),
  );
  return (proc, p);
}

void main() {
  group('Étape 2 — client HTTP offline (sans téléphone)', skip: !_run, () {
    late Process api;
    late GafesoApi client;
    late String userId;
    late String baseUrl;
    late GafesoApi bib;
    late Directory tmp;

    // Clé « appareil » : EC P-256 générée par openssl (tient le rôle du keystore, absent hors device).
    late String devicePubB64;
    late File devicePrivPk8;

    setUpAll(() async {
      final started = await _startApi();
      api = started.$1;
      tmp = await Directory.systemTemp.createTemp('gafeso-step2-');

      // Paire EC P-256 : privée en PKCS8 PEM (lisible par la JVM), publique en SPKI DER b64.
      final pem = File('${tmp.path}/dev_ec.pem');
      devicePrivPk8 = File('${tmp.path}/dev_ec_pk8.pem');
      final pubDer = File('${tmp.path}/dev_ec_pub.der');
      await Process.run('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', pem.path]);
      await Process.run('openssl', ['pkcs8', '-topk8', '-nocrypt', '-in', pem.path, '-out', devicePrivPk8.path]);
      await Process.run('openssl', ['ec', '-in', pem.path, '-pubout', '-outform', 'DER', '-out', pubDer.path]);
      devicePubB64 = base64Encode(await pubDer.readAsBytes());

      final base = 'http://127.0.0.1:${started.$2}';
      final mdp = _recettePassword();

      // ⚠ VRAIE CONNEXION, comme l'application. Aucun jeton fabriqué.
      client = GafesoApi(baseUrl: base, tenantSlug: 'zinda');
      final rEtu = await client.login(email: 'recette-etu@exemple.bf', password: mdp);
      expect(rEtu.accessToken, isNotNull,
          reason: 'recette-etu@ ne se connecte pas — `npm run comptes:recette` ?');
      userId = rEtu.userId!;

      // Le comptoir : c'est lui qui a le droit de révoquer (catalogue.gerer).
      bib = GafesoApi(baseUrl: base, tenantSlug: 'zinda');
      final rBib = await bib.login(email: 'recette-bib@exemple.bf', password: mdp);
      expect(rBib.accessToken, isNotNull, reason: 'recette-bib@ ne se connecte pas');
      baseUrl = base;
    });

    tearDownAll(() async {
      client.close();
      bib.close();
      api.kill(ProcessSignal.sigterm);
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('device EC → licence → CEK EC-KEM → blob → %PDF → révocation → purge', () async {
      // 1) Enregistrement de l'appareil avec la clé publique EC (validation backend : P-256).
      final deviceId = await client.registerDevice(
        publicKeySpkiB64: devicePubB64,
        label: 'test-sans-telephone',
      );
      expect(deviceId, isNotEmpty);

      // 2) L'étagère expose le document que le script de recette a préparé,
      //    par les routes du produit. On ne le fabrique pas, on le CONSTATE.
      final shelf = await client.myDocuments();
      expect(shelf, isNotEmpty,
          reason: 'recette-etu@ n’a aucun document hors ligne préparé — '
              'relancer `npm run comptes:recette`');
      final docId = shelf.first.docId;

      // 3) Émission de la licence (le serveur vérifie le droit réel).
      final lic = await client.issueLicense(docId: docId, deviceId: deviceId);
      expect(lic.body['v'], 1, reason: 'version de licence EC-KEM');
      expect(lic.tenant, 'zinda');
      expect(lic.deviceId, deviceId);
      expect(lic.userId, userId);

      // L'enveloppe est bien de l'EC-KEM v1 (et pas un chiffré RSA brut).
      final wrapped = jsonDecode(lic.wrappedCek) as Map<String, dynamic>;
      expect(wrapped['v'], 1);
      expect(wrapped.keys, containsAll(<String>['epk', 'nonce', 'ct']));

      // 4) Statut initial.
      expect(await client.licenseStatus(lic.licenseId), 'active');

      // 5) URL signée + téléchargement du blob CHIFFRÉ.
      final blob = await client.blobUrl(lic.licenseId);
      final dest = File('${tmp.path}/doc.gafs');
      final size = await client.downloadBlob(url: blob.url, dest: dest);
      expect(size, greaterThan(0));
      // Au repos : magic GAFS1, jamais %PDF.
      final head = await dest.openRead(0, 5).first;
      expect(utf8.decode(head), 'GAFS1');

      // 6) Preuve que le CODE APPAREIL (Kotlin réel, harnais JVM) exploite cette licence :
      //    vérif Ed25519 + déballage CEK EC-KEM + déchiffrement du blob jusqu'à %PDF.
      final wrappedFile = File('${tmp.path}/wrapped.json')..writeAsStringSync(lic.wrappedCek);
      final bodyFile = File('${tmp.path}/body.json')..writeAsStringSync(lic.bodyJson);
      final sigFile = File('${tmp.path}/sig.b64')..writeAsStringSync(lic.signature);
      final pubFile = File('${tmp.path}/lic_pub.pem')..writeAsStringSync(lic.licensePublicKey);

      final jvm = await Process.run(_java, [
        '-cp',
        '$_xvec/step2.jar:$_kotlinLib/kotlin-stdlib-1.9.23.jar:$_xvec/lib/json.jar',
        'com.gafeso.spikeb.Step2VectorKt',
        devicePrivPk8.path, wrappedFile.path, deviceId,
        bodyFile.path, sigFile.path, pubFile.path, dest.path,
      ]);
      // ignore: avoid_print
      print('JVM(appareil) → ${jvm.stdout}'.trim());
      expect(jvm.exitCode, 0, reason: 'harnais JVM : ${jvm.stderr}');
      expect(jvm.stdout, contains('STEP2_OK'));
      expect(jvm.stdout, contains('sig=true'));
      expect(jvm.stdout, contains('head=%PDF-'));

      // 7) Révocation PAR LA ROUTE DU PRODUIT, avec le compte du comptoir —
      //    `catalogue.gerer`. Plus d'écriture directe en base : on révoque comme
      //    un bibliothécaire révoque, et c'est ce chemin-là qu'il faut éprouver.
      final req = await HttpClient().postUrl(
        Uri.parse('$baseUrl/offline/licenses/${lic.licenseId}/revoke'),
      );
      req.headers.set('X-Tenant', 'zinda');
      req.headers.set('Authorization', 'Bearer ${bib.token}');
      final rep = await req.close();
      await rep.drain<void>();
      expect(rep.statusCode, lessThan(400), reason: 'révocation refusée (${rep.statusCode})');

      expect(await client.licenseStatus(lic.licenseId), 'revoked');

      // 8) Le blob n'est plus téléchargeable (licence non active).
      await expectLater(
        client.blobUrl(lic.licenseId),
        throwsA(isA<GafesoApiException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
