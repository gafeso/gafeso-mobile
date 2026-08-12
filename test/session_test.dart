import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/session/library_store.dart';
import 'package:gafeso_mobile/session/session.dart';

/// Coffre natif simulé : le vrai chiffre par le keystore (indisponible hors device) ; on
/// vérifie ici la logique Dart qui s'appuie dessus (sérialisation, purge, tolérance aux
/// données illisibles).
class _FakeSecureStore {
  final Map<String, String> values = {};
  int removeCalls = 0;

  MethodChannel install(String name) {
    final channel = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'put':
          values[call.arguments['name'] as String] = call.arguments['value'] as String;
          return true;
        case 'get':
          return values[call.arguments['name'] as String];
        case 'remove':
          removeCalls++;
          values.remove(call.arguments['name'] as String);
          return true;
        case 'clear':
          values.clear();
          return true;
      }
      return null;
    });
    return channel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSession', () {
    const s = AppSession(
      tenantSlug: 'zinda',
      token: 'jwt',
      userId: 'u1',
      displayName: 'Awa Traoré',
      email: 'awa@exemple.bf',
      role: 'STUDENT',
    );

    test('aller-retour JSON', () {
      final back = AppSession.fromJson(s.toJson());
      expect(back.tenantSlug, 'zinda');
      expect(back.userId, 'u1');
      expect(back.displayName, 'Awa Traoré');
      expect(back.role, 'STUDENT');
    });

    test('le filigrane porte le nom, l’école et l’horodatage', () {
      final w = s.watermark(DateTime.utc(2026, 7, 29, 14, 5));
      expect(w, contains('Awa Traoré'));
      expect(w, contains('zinda'));
      expect(w, contains('2026-07-29 14:05'));
    });
  });

  group('SessionStore (coffre natif simulé)', () {
    late _FakeSecureStore fake;
    late SessionStore store;

    setUp(() {
      fake = _FakeSecureStore();
      store = SessionStore(channel: fake.install('com.gafeso/secure'));
    });

    test('écrit la session ET mémorise l’école', () async {
      await store.write(const AppSession(
        tenantSlug: 'zinda', token: 't', userId: 'u1', displayName: 'Awa'));
      expect(await store.readTenant(), 'zinda');
      expect((await store.read())!.userId, 'u1');
      // Rien n'est stocké en clair par nos soins : la valeur passe au natif, qui chiffre.
      expect(fake.values.keys, containsAll(<String>['session', 'tenant']));
    });

    test('déconnexion : la session part, l’école reste', () async {
      await store.write(const AppSession(
        tenantSlug: 'zinda', token: 't', userId: 'u1', displayName: 'Awa'));
      await store.clearSession();
      expect(await store.read(), isNull);
      expect(await store.readTenant(), 'zinda');
    });

    test('session illisible → purgée et traitée comme absente', () async {
      fake.values['session'] = 'ceci-nest-pas-du-json';
      expect(await store.read(), isNull);
      expect(fake.removeCalls, greaterThan(0));
    });
  });

  group('LibraryStore', () {
    late _FakeSecureStore fake;
    late LibraryStore lib;

    const doc = LocalDocument(
      docId: 'd1',
      title: 'Thèse',
      licenseId: 'lic1',
      licenseBody: '{"v":1,"userId":"u1","tenant":"zinda"}',
      signature: 'sig',
      licensePublicKey: 'pem',
      wrappedCek: '{"v":1}',
      blobPath: '/tmp/d1.gafs',
    );

    setUp(() {
      fake = _FakeSecureStore();
      lib = LibraryStore(channel: fake.install('com.gafeso/secure'));
    });

    test('upsert / get / remove', () async {
      await lib.upsert(doc);
      expect((await lib.get('d1'))!.title, 'Thèse');
      await lib.remove('d1');
      expect(await lib.get('d1'), isNull);
    });

    test('le statut est mis à jour sans perdre la licence', () async {
      await lib.upsert(doc);
      await lib.upsert(doc.copyWith(lastStatus: 'revoked'));
      final back = await lib.get('d1');
      expect(back!.lastStatus, 'revoked');
      expect(back.wrappedCek, '{"v":1}');
    });

    test('bibliothèque corrompue → repartie vide', () async {
      fake.values['library'] = '<<corrompu>>';
      expect(await lib.readAll(), isEmpty);
    });
  });
}
