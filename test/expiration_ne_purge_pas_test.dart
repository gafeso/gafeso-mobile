import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/app_state.dart';
import 'package:gafeso_mobile/session/session.dart';

/// ⚠ UNE SESSION EXPIRÉE N'EST PAS UNE DÉCONNEXION.
///
/// `logout()` purge la bibliothèque locale, et c'est juste : le lecteur rend
/// l'appareil, le contenu part avec. Une expiration n'est le choix de personne.
/// Le jeton vivant un jour, purger à l'expiration effacerait chaque jour le
/// seul travail que le produit existe pour rendre possible : lire sans réseau.
///
/// Ce test garde cette distinction, qui ne se voit pas à la lecture du code —
/// les deux chemins se ressemblent, et l'un appelle `purgeEverything`.
void main() {
  late Map<String, String> coffre;
  late Directory tmp;

  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gafeso-exp-');
    coffre = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
      switch (call.method) {
        case 'put':
          coffre[call.arguments['name'] as String] = call.arguments['value'] as String;
          return true;
        case 'get':
          return coffre[call.arguments['name'] as String];
        case 'remove':
          coffre.remove(call.arguments['name'] as String);
          return true;
        case 'clear':
          coffre.clear();
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Un document déjà téléchargé, tel que la bibliothèque locale le range.
  const bibliotheque = '{"doc-1":{"docId":"doc-1","title":"Thèse hors ligne",'
      '"licenseId":"lic-1","licenseBody":"{}","signature":"sig",'
      '"licensePublicKey":"pk","wrappedCek":"wc","blobPath":"/tmp/doc-1.gafs"}}';

  Future<AppState> etatConnecte() async {
    coffre['tenant'] = 'zinda';
    coffre['session'] = jsonEncode(const AppSession(
      tenantSlug: 'zinda',
      token: 'jeton-du-jour',
      userId: 'u-1',
      displayName: 'Awa',
    ).toJson());
    coffre['library'] = bibliotheque;

    final state = AppState(
      apiBaseUrl: 'http://127.0.0.1:1',
      storageDir: tmp,
      sessionStore: SessionStore(),
    );
    await state.restore();
    return state;
  }

  test('⚠ l’expiration NE PURGE PAS la bibliothèque hors ligne', () async {
    final state = await etatConnecte();
    expect(state.stage, AppStage.shelf, reason: 'on part connecté');

    await state.sessionExpiree();

    expect(coffre['library'], bibliotheque,
        reason: 'les documents téléchargés survivent à un jeton périmé');
    expect(coffre['session'], isNull, reason: 'seule la session est effacée');
    state.dispose();
  });

  test('l’expiration ramène à la connexion et NOMME la cause', () async {
    final state = await etatConnecte();

    await state.sessionExpiree();

    expect(state.stage, AppStage.login);
    expect(state.session, isNull);
    expect(state.sessionNotice, isNotNull);
    expect(state.sessionNotice, contains('expiré'));
    // Elle dit aussi ce qui N'EST PAS perdu : sans cela, « session expirée »
    // laisse craindre que les documents aient disparu avec.
    expect(state.sessionNotice, contains('téléchargés'));
    state.dispose();
  });

  test('idempotente : plusieurs requêtes en vol signalent la même perte', () async {
    final state = await etatConnecte();
    var avis = 0;
    state.addListener(() => avis++);

    await state.sessionExpiree();
    await state.sessionExpiree();
    await state.sessionExpiree();

    expect(avis, 1, reason: 'un seul basculement, pas trois');
    state.dispose();
  });

  test('⚠ la DÉCONNEXION, elle, purge bien — la distinction est gardée', () async {
    final state = await etatConnecte();

    await state.logout();

    expect(coffre['library'], anyOf(isNull, '{}'),
        reason: 'rendre l’appareil emporte le contenu');
    state.dispose();
  });
}
