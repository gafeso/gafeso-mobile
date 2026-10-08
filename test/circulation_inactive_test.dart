import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/app_state.dart';
import 'package:gafeso_mobile/cache/offline_cache.dart';
import 'package:gafeso_mobile/session/session.dart';

/// **Un établissement sans comptoir ne doit pas voir de comptoir.**
///
/// Une université virtuelle n'a ni exemplaire, ni carte, ni prêt. Le serveur le
/// dira de deux façons — `GET /modules`, et le refus des routes `/reader/*` —
/// et la seconde est la plus sûre : elle vient de la route même que l'entrée de
/// menu allait ouvrir.
///
/// Ce que ces cas tiennent : reconnaître le refus sans le confondre avec une
/// panne, et ne RIEN afficher quand on le reconnaît.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GafesoApiException refus(int code, String message) =>
      GafesoApiException(code, '{"message":"$message","statusCode":$code}', '/reader/loans');

  group('reconnaître le refus « circulation inactive »', () {
    test('le libellé attendu de la passation backend', () {
      expect(refus(403, 'module circulation inactif').circulationInactive, isTrue);
    });

    test('les variantes de forme, parce que le libellé n’est pas encore figé', () {
      for (final m in [
        'Module circulation inactif',
        'Le module « circulation » est désactivé pour cet établissement.',
        'circulation module is disabled',
        'Circulation non disponible',
        'module circulation hors service',
      ]) {
        expect(refus(403, m).circulationInactive, isTrue, reason: m);
      }
      // 404 et 501 disent la même chose : la capacité n'existe pas ici.
      expect(refus(404, 'module circulation inactif').circulationInactive, isTrue);
      expect(refus(501, 'module circulation inactif').circulationInactive, isTrue);
    });

    test('⚠ une PANNE n’est jamais lue comme une absence de circulation', () {
      // Le cas qui compte : amputer le menu d'une vraie bibliothèque sur un
      // incident passager serait pire que l'entrée de trop qu'on corrige ici.
      expect(refus(500, 'module circulation inactif').circulationInactive, isFalse);
      expect(refus(502, 'circulation indisponible').circulationInactive, isFalse);
    });

    test('⚠ un refus qui ne nomme pas la circulation inactive ne compte pas', () {
      expect(refus(403, 'Appareil inconnu ou révoqué.').circulationInactive, isFalse);
      expect(refus(403, 'Vous n’avez aucun prêt en circulation.').circulationInactive, isFalse);
      expect(refus(403, 'Document pas encore préparé.').circulationInactive, isFalse);
      expect(GafesoApiException(403, '<html>503</html>', '/reader/card').circulationInactive,
          isFalse);
    });
  });

  group('ne rien afficher quand on le reconnaît', () {
    final coffre = <String, String>{};
    setUp(() {
      coffre.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
        final nom = (call.arguments as Map?)?['name'] as String?;
        if (call.method == 'get') return coffre[nom];
        if (call.method == 'put') coffre[nom!] = (call.arguments as Map)['value'] as String;
        if (call.method == 'remove') coffre.remove(nom);
        return null;
      });
    });

    test('le refus ne produit AUCUNE erreur à l’écran', () async {
      final r = await loadCached<List<String>>(
        cache: OfflineCache(),
        resource: 'reader.loans',
        fromJson: (j) => (j as List).cast<String>(),
        toJson: (v) => v,
        fetch: () async => throw refus(403, 'module circulation inactif'),
      );
      expect(r.lastError, isNull, reason: 'un module absent n’est pas une panne');
    });

    test('témoin : une VRAIE panne, elle, est signalée', () async {
      final r = await loadCached<List<String>>(
        cache: OfflineCache(),
        resource: 'reader.loans',
        fromJson: (j) => (j as List).cast<String>(),
        toJson: (v) => v,
        fetch: () async => throw refus(500, 'Erreur interne'),
      );
      expect(r.lastError, isNotNull);
    });
  });

  group('ce que l’app en fait', () {
    AppState etat() => AppState(
          apiBaseUrl: 'http://127.0.0.1:1',
          storageDir: Directory.systemTemp.createTempSync('gafeso-circ'),
          sessionStore: SessionStore(),
        );

    test('par défaut, tant qu’on ne sait pas, on montre TOUT', () {
      final s = etat();
      expect(s.circulationActive, isTrue);
      expect(s.titreEtagere, 'Mon étagère');
    });

    test('après le refus : plus de carte, plus de prêts, et le mot juste', () {
      final s = etat();
      s.circulationInactive();
      expect(s.circulationActive, isFalse);
      // « étagère » et « prêt » n'ont pas de référent sans comptoir.
      expect(s.titreEtagere, 'Mes documents hors ligne');
    });

    test('le refus ne notifie qu’UNE fois — il arrive de trois routes', () {
      final s = etat();
      var avis = 0;
      s.addListener(() => avis++);
      s.circulationInactive(); // /reader/card
      s.circulationInactive(); // /reader/loans
      s.circulationInactive(); // /reader/holds
      expect(avis, 1);
    });
  });
}
