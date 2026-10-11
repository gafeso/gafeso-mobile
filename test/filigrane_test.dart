import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/api/offline_service.dart';
import 'package:gafeso_mobile/session/library_store.dart';
import 'package:gafeso_mobile/session/session.dart';

/// ⚠ **LE FILIGRANE PORTE TROIS CHOSES, ET AUCUNE NE DOIT DISPARAÎTRE EN
/// SILENCE.**
///
/// Vérifié sur le téléphone de Jean le 09/10/2026 : chaque page affiche
/// l'établissement, l'horodatage à la minute et le nom du lecteur. C'est la
/// contrepartie donnée aux auteurs des travaux qu'on laisse emporter — et c'est
/// aussi ce qui rend une photographie d'écran attribuable.
///
/// ⚠ CE TEST NE DEMANDE AUCUN CHANGEMENT. Le filigrane est juste ; il s'agit
/// d'empêcher qu'une réécriture future en retire un morceau sans que rien ne
/// s'en aperçoive. Une protection qui s'efface discrètement est pire que pas de
/// protection : on continue de la promettre.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const session = AppSession(
    tenantSlug: 'gafeso-univ',
    token: 'jeton',
    userId: 'u-1',
    displayName: 'Justine Ilboudo',
    role: 'STUDENT',
  );
  final instant = DateTime.utc(2026, 10, 9, 22, 5);

  /// Les trois éléments, cherchés un à un dans un filigrane quelconque.
  ///
  /// ⚠ C'est cette fonction que le contrôle négatif éprouve : si elle se
  /// trompait, tous les cas ci-dessous passeraient sans rien garantir.
  ({bool etablissement, bool horodatage, bool identite}) elements(
    String filigrane, {
    required AppSession s,
    required DateTime t,
  }) {
    final jour = '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
    final minute = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return (
      etablissement: filigrane.contains(s.tenantSlug),
      // Jour ET minute : une date sans heure ne situe pas une capture, et une
      // heure sans date ne vaut rien passé minuit.
      horodatage: filigrane.contains(jour) && filigrane.contains(minute),
      identite: filigrane.contains(s.displayName),
    );
  }

  group('⚠ LES TROIS ÉLÉMENTS SONT LÀ', () {
    test('établissement, horodatage à la minute, identité du lecteur', () {
      final w = session.watermark(instant);
      final e = elements(w, s: session, t: instant);
      expect(e.etablissement, isTrue, reason: 'l’établissement a disparu : $w');
      expect(e.horodatage, isTrue, reason: 'l’horodatage a disparu : $w');
      expect(e.identite, isTrue, reason: 'le nom du lecteur a disparu : $w');
    });

    test('⚠ à la MINUTE, ni plus grossier ni plus fin', () {
      final w = session.watermark(instant);
      // Plus grossier : une capture ne serait plus situable dans la journée.
      expect(w, contains('22:05'));
      // Plus fin : les secondes n'ajoutent rien et rendent le filigrane
      // illisible sur une page.
      expect(w, isNot(contains('22:05:00')));
    });
  });

  group('⚠ CHAQUE ÉLÉMENT VIENT DE LA SESSION — il n’est pas écrit en dur', () {
    // Un filigrane qui afficherait « gafeso-univ » en constante passerait les
    // cas ci-dessus et ne désignerait plus personne. On fait VARIER l'entrée.
    test('changer d’établissement change le filigrane', () {
      const autre = AppSession(
        tenantSlug: 'zinda',
        token: 'j',
        userId: 'u-1',
        displayName: 'Justine Ilboudo',
      );
      expect(autre.watermark(instant), isNot(session.watermark(instant)));
      expect(autre.watermark(instant), contains('zinda'));
    });

    test('changer de lecteur change le filigrane', () {
      const autre = AppSession(
        tenantSlug: 'gafeso-univ',
        token: 'j',
        userId: 'u-2',
        displayName: 'Awa Traoré',
      );
      expect(autre.watermark(instant), contains('Awa Traoré'));
      expect(autre.watermark(instant), isNot(contains('Justine Ilboudo')));
    });

    test('changer d’instant change le filigrane', () {
      final plusTard = instant.add(const Duration(minutes: 1));
      expect(session.watermark(plusTard), isNot(session.watermark(instant)));
      expect(session.watermark(plusTard), contains('22:06'));
    });
  });

  group('⚠ CONTRÔLE NÉGATIF — la vérification sait voir une disparition', () {
    test('un filigrane amputé de l’établissement est DÉTECTÉ', () {
      // Sans ce cas, `elements` pourrait rendre « tout présent » par erreur et
      // les assertions ci-dessus applaudiraient un filigrane vidé.
      final e = elements('Justine Ilboudo · 2026-10-09 22:05',
          s: session, t: instant);
      expect(e.etablissement, isFalse);
      expect(e.horodatage, isTrue);
      expect(e.identite, isTrue);
    });

    test('un filigrane amputé de l’horodatage est DÉTECTÉ', () {
      final e = elements('Justine Ilboudo · gafeso-univ', s: session, t: instant);
      expect(e.horodatage, isFalse);
    });

    test('un filigrane amputé du nom est DÉTECTÉ', () {
      final e = elements('gafeso-univ · 2026-10-09 22:05', s: session, t: instant);
      expect(e.identite, isFalse);
    });

    test('⚠ une DATE SEULE ne passe pas pour un horodatage', () {
      // Le cas le plus plausible d'une réécriture : garder le jour, perdre
      // l'heure. La capture cesse alors d'être situable dans la journée.
      final e = elements('Justine Ilboudo · gafeso-univ · 2026-10-09',
          s: session, t: instant);
      expect(e.horodatage, isFalse);
    });

    test('un filigrane VIDE est détecté sur les trois', () {
      final e = elements('', s: session, t: instant);
      expect(e.etablissement, isFalse);
      expect(e.horodatage, isFalse);
      expect(e.identite, isFalse);
    });
  });

  group('⚠ ET IL ARRIVE INTACT AU LECTEUR NATIF', () {
    // Le filigrane le mieux composé ne sert à rien s'il se perd en chemin : il
    // est peint par la vue native, qui le reçoit dans les paramètres d'ouverture.
    late Directory tmp;
    late Map<String, String> coffre;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('gafeso-filigrane-');
      coffre = {};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (c) async {
        final nom = (c.arguments as Map?)?['name'] as String?;
        if (c.method == 'get') return coffre[nom];
        if (c.method == 'put') coffre[nom!] = (c.arguments as Map)['value'] as String;
        if (c.method == 'remove') coffre.remove(nom);
        return null;
      });
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('openParams transmet le filigrane sans le toucher', () async {
      final blob = File('${tmp.path}/d1.gafs')..writeAsBytesSync([1, 2, 3]);
      final service = OfflineService(
        api: GafesoApi(baseUrl: 'http://127.0.0.1:1', tenantSlug: 'gafeso-univ'),
        storageDir: tmp,
      );
      addTearDown(service.api.close);
      await service.library.upsert(LocalDocument(
        docId: 'd1',
        title: 'Une thèse',
        licenseId: 'l1',
        licenseBody: '{"userId":"u-1","tenant":"gafeso-univ"}',
        signature: 's',
        licensePublicKey: 'p',
        wrappedCek: 'w',
        blobPath: blob.path,
      ));

      final attendu = session.watermark(instant);
      final params = await service.openParams(docId: 'd1', watermark: attendu);

      expect(params, isNotNull);
      expect(params!['watermark'], attendu,
          reason: 'le filigrane a été modifié ou perdu en chemin');
      final e = elements(params['watermark'] as String, s: session, t: instant);
      expect([e.etablissement, e.horodatage, e.identite], [true, true, true]);
    });
  });
}
