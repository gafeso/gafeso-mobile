import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/session/library_store.dart';

/// VERSIONNEMENT DE L'ÉTAT LOCAL.
///
/// ⚠ Pourquoi ce lot existe : une installation de SIX SEMAINES survit à une
/// réinstallation par-dessus — mesuré sur téléphone réel. Des usagers gardent
/// donc des états anciens, et cette dette grandit toute seule.
///
/// Et le danger n'était pas « casser en silence » : l'ancien `readAll`
/// enveloppait toute la boucle dans un seul `try` et PURGEAIT la clé au premier
/// échec. Une entrée abîmée emportait l'étagère entière.
void main() {
  late Map<String, String> coffre;

  Map<String, dynamic> docJson(String id) => {
        'docId': id,
        'title': 'Titre $id',
        'licenseId': 'lic-$id',
        'licenseBody': jsonEncode({'v': 1, 'expiresAt': '2026-12-01T00:00:00Z'}),
        'signature': 'sig',
        'licensePublicKey': 'pk',
        'wrappedCek': 'wc',
        'blobPath': '/tmp/$id.gafs',
      };

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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

  LibraryStore store() => LibraryStore();

  group('compatibilité ascendante', () {
    test('⚠ un état SANS version (forme d’août) est lu', () async {
      // La forme d'avant le numérotage : la table nue, sans enveloppe.
      coffre['library'] = jsonEncode({'d1': docJson('d1')});
      final docs = await store().readAll();
      expect(docs.keys, ['d1']);
      expect(docs['d1']!.title, 'Titre d1');
    });

    test('… et il est MIGRÉ vers le schéma courant', () async {
      coffre['library'] = jsonEncode({'d1': docJson('d1')});
      await store().readAll();
      final relu = jsonDecode(coffre['library']!) as Map;
      expect(relu['v'], LibraryStore.schemaVersion);
      expect((relu['docs'] as Map).keys, ['d1']);
    });

    test('un état versionné se relit', () async {
      coffre['library'] =
          jsonEncode({'v': 1, 'docs': {'d1': docJson('d1')}});
      expect((await store().readAll()).keys, ['d1']);
    });
  });

  group('⚠ AUCUNE DESTRUCTION — c’est le point du lot', () {
    test('une entrée illisible est écartée, les AUTRES survivent', () async {
      // Le comportement d'avant : la clé entière était supprimée.
      coffre['library'] = jsonEncode({
        'bon': docJson('bon'),
        'abime': {'docId': 'abime'}, // champs obligatoires absents
        'bon2': docJson('bon2'),
      });
      final s = store();
      final docs = await s.readAll();

      expect(docs.keys.toSet(), {'bon', 'bon2'});
      expect(s.dernierProbleme, contains('illisible'));
      expect(coffre['library'], isNotNull, reason: 'rien n’a été effacé');
    });

    test('⚠ et l’entrée écartée n’est pas RÉÉCRITE hors de l’état', () async {
      // Migrer après avoir écarté une entrée la supprimerait pour de bon.
      coffre['library'] = jsonEncode({
        'bon': docJson('bon'),
        'abime': {'docId': 'abime'},
      });
      await store().readAll();
      final brut = jsonDecode(coffre['library']!) as Map;
      expect(brut.containsKey('abime'), isTrue,
          reason: 'l’état d’origine est intact, examinable');
    });

    test('⚠ une version PLUS RÉCENTE est laissée intacte', () async {
      // Retour en arrière d'installation : on ne comprend pas, on ne détruit pas.
      final futur = jsonEncode({'v': 99, 'docs': {'d1': docJson('d1')}});
      coffre['library'] = futur;
      final s = store();
      expect(await s.readAll(), isEmpty);
      expect(s.dernierProbleme, contains('plus récente'));
      expect(coffre['library'], futur, reason: 'octet pour octet');
    });

    test('un contenu totalement illisible est signalé, pas effacé', () async {
      coffre['library'] = 'ceci n’est pas du JSON';
      final s = store();
      expect(await s.readAll(), isEmpty);
      expect(s.dernierProbleme, contains('illisible'));
      expect(coffre['library'], 'ceci n’est pas du JSON');
    });

    test('une bibliothèque vide n’est pas un problème', () async {
      final s = store();
      expect(await s.readAll(), isEmpty);
      expect(s.dernierProbleme, isNull);
    });
  });
}
