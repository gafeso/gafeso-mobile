/// E2E du parcours MVP (Étape 3) — **SANS TÉLÉPHONE**, contre le vrai backend.
///
/// Gaté par `MOBILE_E2E=1` (mêmes prérequis que l'e2e de l'Étape 2 : dépôt backend +
/// infra dev up). Enchaîne les trois écrans **par leur logique** :
///   1. école : code décodé (QR ou saisie) → `X-Tenant` mémorisé ;
///   2. connexion : vrai `POST /auth/login` → session offline (identité + filigrane) ;
///   3. étagère : `GET /offline/my-documents` → téléchargement (licence + blob) → paramètres
///      d'ouverture du lecteur **lus depuis la bibliothèque locale** (donc utilisables
///      hors-ligne) → re-check de statut après révocation → **purge**.
///
/// Les canaux natifs (keystore EC, coffre chiffré) sont simulés : indisponibles hors device.
/// Ce qu'ils font est prouvé ailleurs (cross-vector EC, preuve device Étape 1).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/app_state.dart';
import 'package:gafeso_mobile/session/session.dart';
import 'package:gafeso_mobile/session/tenant_code.dart';

final _run = Platform.environment['MOBILE_E2E'] == '1';
final _backendDir = Platform.environment['GAFESO_BACKEND_DIR'] ??
    '${Platform.environment['HOME']}/bibliocloud';

/// Mot de passe des comptes de démonstration, LU DANS L'ENVIRONNEMENT.
///
/// Il était écrit en dur ici. Deux raisons de ne plus le faire : un mot de passe
/// versionné est un mot de passe publié, et celui-ci était de toute façon devenu
/// faux — `seed-demo.mjs` tire désormais le mot de passe au hasard à chaque
/// Mot de passe des comptes de RECETTE, lu dans le `.env` du backend.
///
/// ⚠ CE TEST SE CONNECTAIT AU COMPTE DE DÉMONSTRATION, dont le mot de passe est
/// tiré au hasard à chaque exécution du seed — il fallait donc rejouer le seed
/// et exporter la même valeur, et le test échouait sinon sans que la cause soit
/// lisible. Les comptes de recette ont un mot de passe FIXE, posé par
/// `npm run comptes:recette`, et ils n'appartiennent à aucune démonstration :
/// s'en servir n'abîme plus rien.
///
/// Le mot de passe n'est ni affiché ni journalisé.
String get _recettePassword {
  final f = File('$_backendDir/.env');
  if (f.existsSync()) {
    for (final l in f.readAsLinesSync()) {
      if (l.startsWith('RECETTE_PASSWORD=')) {
        final v = l.substring('RECETTE_PASSWORD='.length).trim();
        if (v.isNotEmpty) return v;
      }
    }
  }
  throw StateError(
    'RECETTE_PASSWORD introuvable dans $_backendDir/.env. '
    'Lancez `npm run comptes:recette` dans le dépôt backend.',
  );
}

Future<String> _backendScript(List<String> args) async {
  final res = await Process.run(
    'npx',
    [
      'dotenv', '-e', '../../.env', '--',
      'npx', 'ts-node', '--transpile-only',
      '--compiler-options', '{"module":"commonjs"}',
      'scripts/mobile-e2e-fixture.ts',
      ...args,
    ],
    workingDirectory: '$_backendDir/apps/api',
    environment: {...Platform.environment, 'TS_NODE_TRANSPILE_ONLY': '1'},
  );
  if (res.exitCode != 0) {
    throw StateError('fixture ${args.first} : ${res.stderr}\n${res.stdout}');
  }
  return (res.stdout as String).trim().split('\n').last;
}

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
  final p = await port.future
      .timeout(const Duration(seconds: 90), onTimeout: () => throw StateError('API KO : $err'));
  return (proc, p);
}

/// Coffre natif simulé (le vrai chiffre via keystore, indisponible hors device).
Map<String, String> _installFakeSecure() {
  final values = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.gafeso/secure'),
    (call) async {
      switch (call.method) {
        case 'put':
          values[call.arguments['name'] as String] = call.arguments['value'] as String;
          return true;
        case 'get':
          return values[call.arguments['name'] as String];
        case 'remove':
          values.remove(call.arguments['name'] as String);
          return true;
        case 'clear':
          values.clear();
          return true;
      }
      return null;
    },
  );
  return values;
}

/// Appareil simulé : clé EC P-256 réelle (openssl), id mémorisé comme le ferait le natif.
Future<void> _installFakeDevice(Directory tmp) async {
  final pem = File('${tmp.path}/dev_ec.pem');
  final pubDer = File('${tmp.path}/dev_ec_pub.der');
  await Process.run('openssl', ['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', pem.path]);
  await Process.run('openssl', ['ec', '-in', pem.path, '-pubout', '-outform', 'DER', '-out', pubDer.path]);
  final pub = base64Encode(await pubDer.readAsBytes());
  String? deviceId;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('com.gafeso/device'),
    (call) async {
      switch (call.method) {
        case 'publicKey':
          return pub;
        case 'deviceId':
          return deviceId ?? 'empreinte-locale';
        case 'isRegistered':
          return deviceId != null;
        case 'storeDeviceId':
          deviceId = call.arguments['deviceId'] as String;
          return true;
        case 'clearDeviceId':
          deviceId = null;
          return true;
      }
      return null;
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Parcours MVP (école → connexion → étagère), sans téléphone', skip: !_run, () {
    late Process api;
    late Map<String, dynamic> fx;
    late Directory tmp;
    late AppState state;

    setUpAll(() async {
      // ⚠ TestWidgetsFlutterBinding (requis pour simuler les canaux natifs) installe un
      // HttpOverrides qui fait échouer TOUTE requête réelle en 400. On le neutralise : ce test
      // parle au vrai backend.
      HttpOverrides.global = null;

      final started = await _startApi();
      api = started.$1;
      tmp = await Directory.systemTemp.createTemp('gafeso-mvp-');
      _installFakeSecure();
      await _installFakeDevice(tmp);
      fx = jsonDecode(await _backendScript(['create'])) as Map<String, dynamic>;

      state = AppState(
        apiBaseUrl: 'http://127.0.0.1:${started.$2}',
        storageDir: tmp,
        sessionStore: SessionStore(),
      );
      await state.restore();
    });

    tearDownAll(() async {
      try {
        await _backendScript(['cleanup', jsonEncode(fx)]);
      } catch (_) {/* tolérant */}
      state.dispose();
      api.kill(ProcessSignal.sigterm);
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('école → connexion → étagère → lecture hors-ligne → révocation → purge', () async {
      // ── Écran 1 : école (via un QR au format applicatif) ──────────────────────
      expect(state.stage, AppStage.tenant, reason: 'aucune école mémorisée au départ');
      final slug = TenantCode.parse('gafeso://tenant/${fx['tenant']}');
      expect(slug, fx['tenant']);
      await state.setTenant(slug!);
      expect(state.stage, AppStage.login);

      // ── Écran 2 : connexion réelle (JWT) ──────────────────────────────────────
      final badLogin = await state.login(email: 'recette-etu@exemple.bf', password: 'mauvais');
      expect(badLogin, isNotNull, reason: 'un mauvais mot de passe doit être refusé');
      expect(state.stage, AppStage.login);

      final err = await state.login(email: 'recette-etu@exemple.bf', password: _recettePassword);
      expect(err, isNull, reason: 'connexion refusée : $err');
      expect(state.stage, AppStage.shelf);
      expect(state.session!.userId, fx['userId']);
      // Le filigrane porte l'identité et l'école (il sera incrusté par le natif au rendu).
      final watermark = state.session!.watermark(DateTime.utc(2026, 7, 29, 10, 0));
      expect(watermark, contains('zinda'));
      expect(watermark, contains('Awa'));

      // La session est persistée (chiffrée par le natif en production).
      final restored = await state.sessions.read();
      expect(restored!.userId, fx['userId']);

      // ── Écran 3 : étagère ─────────────────────────────────────────────────────
      final shelf = await state.offline.api.myDocuments();
      expect(shelf.map((d) => d.docId), contains(fx['docId']));
      final target = shelf.firstWhere((d) => d.docId == fx['docId']);

      // Téléchargement : licence émise (appareil enregistré au passage) + blob chiffré.
      final doc = await state.offline.download(docId: target.docId, title: target.title);
      expect(File(doc.blobPath).existsSync(), isTrue);
      final head = await File(doc.blobPath).openRead(0, 5).first;
      expect(utf8.decode(head), 'GAFS1', reason: 'le blob reste chiffré au repos');
      expect(jsonDecode(doc.wrappedCek)['v'], 1, reason: 'enveloppe EC-KEM v1');

      // Ouverture : les paramètres du lecteur viennent de la bibliothèque LOCALE → hors-ligne.
      final params = await state.offline.openParams(docId: target.docId, watermark: watermark);
      expect(params, isNotNull);
      expect(params!['blobPath'], doc.blobPath);
      expect(params['tenant'], 'zinda');
      expect(params['userId'], fx['userId']);
      expect(params['watermark'], watermark);

      // Un échec réseau ne doit JAMAIS purger : la licence locale reste exploitable.
      expect(await state.offline.library.get(target.docId), isNotNull);

      // ── Révocation : le droit est retiré en base → re-check → purge ────────────
      await _backendScript(['revoke', fx['accessRuleId'] as String]);
      fx.remove('accessRuleId');

      final statuses = await state.offline.refreshAll();
      expect(statuses[target.docId], 'revoked');
      expect(File(doc.blobPath).existsSync(), isFalse, reason: 'blob purgé');
      expect(await state.offline.library.get(target.docId), isNull, reason: 'licence oubliée');
      expect(await state.offline.openParams(docId: target.docId, watermark: watermark), isNull);
    });
  });
}
