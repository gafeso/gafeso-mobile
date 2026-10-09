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
      //
      // ⚠ COURT, ET MESURÉ : « Mes documents hors ligne » demande 534 dp à la
      // taille d'un titre de barre et ne tient sur aucun écran de 360 dp, même
      // sans une seule icône. Le « hors ligne » vit dans le corps de l'écran.
      expect(s.titreEtagere, 'Mes documents');
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

  group('⚠ LE SERVEUR TRANCHE — un refus transitoire n’ampute plus rien', () {
    AppState etat() => AppState(
          apiBaseUrl: 'http://127.0.0.1:1',
          storageDir: Directory.systemTemp.createTempSync('gafeso-verite'),
          sessionStore: SessionStore(),
        );

    test('⚠ LE CAS CONSTATÉ : refus isolé alors que circulationActive = true', () {
      // Observé une fois sur `recette-etu@` — un compte qui A un prêt et une
      // réservation : l'étagère est passée en profil « bibliothèque numérique »
      // et y est restée jusqu'à la relance, alors que `/tenancy/current`
      // donnait circulation active et que `/reader/*` rendaient 200.
      //
      // Le signal de refus est irréversible pour la session, DÉLIBÉRÉMENT : un
      // signal qui se relève rouvrirait le menu qui ment. Ce qui manquait,
      // c'est qu'il ne pèse rien face à une réponse du serveur.
      final s = etat();
      s.circulationDuServeur = true;
      s.circulationInactive(); // le hoquet
      expect(s.circulationActive, isTrue,
          reason: 'un refus d’une milliseconde a amputé le menu');
      expect(s.titreEtagere, 'Mon étagère');
    });

    test('le serveur dit NON : le menu se ferme, et aucun refus n’est requis', () {
      final s = etat();
      s.circulationDuServeur = false;
      expect(s.circulationActive, isFalse);
      expect(s.titreEtagere, 'Mes documents');
    });

    test('⚠ le serveur se TAIT (antérieur à rc6) : le repli reprend la main', () {
      // Trois états, et le troisième compte : « je ne sais pas » n'est pas
      // « il n'y a pas de comptoir ».
      final s = etat();
      expect(s.circulationDuServeur, isNull);
      expect(s.circulationActive, isTrue, reason: 'sans information, on montre tout');
      s.circulationInactive();
      expect(s.circulationActive, isFalse, reason: 'le repli doit encore servir');
    });

    test('⚠ UN SIGNAL POSITIF ANNULE LA BASCULE — même sans le serveur', () {
      // Une route `/reader/*` qui répond 200 prouve qu'il y a un comptoir.
      final s = etat();
      s.circulationInactive();
      expect(s.circulationActive, isFalse);
      s.circulationConfirmee();
      expect(s.circulationActive, isTrue);
    });

    test('la réponse du serveur efface un refus déjà enregistré', () async {
      final s = etat();
      s.circulationInactive();
      expect(s.circulationActive, isFalse);
      // Ce que fait `chargerCirculation()` quand le serveur répond « true ».
      s.circulationDuServeur = true;
      s.circulationConfirmee();
      expect(s.circulationActive, isTrue);
    });

    test('⚠ TÉMOIN — sans la source de vérité, le refus amputerait bien', () {
      // Sans ce cas, les assertions ci-dessus pourraient passer parce que
      // `circulationInactive()` ne fait plus rien du tout.
      final s = etat();
      var avis = 0;
      s.addListener(() => avis++);
      s.circulationInactive();
      expect(avis, 1, reason: 'le repli a été neutralisé, pas subordonné');
      expect(s.circulationRefusee, isTrue);
    });
  });
}
