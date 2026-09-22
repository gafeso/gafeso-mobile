import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';

/// SESSION PERDUE — le jeton vit un jour, et il n'y a pas de renouvellement.
///
/// Avant ce lot, au lendemain d'une connexion l'app disait deux faux sans
/// jamais ramener vers l'écran de connexion :
///   - l'étagère : « hors ligne », sur un réseau qui marche ;
///   - la fiche  : « Aucun exemplaire physique », sur une notice qui en a.
///
/// Les deux se détectent au même endroit, parce que le serveur les exprime
/// différemment : 401 sur les routes gardées, 200 + `membersOnly` sur la route
/// publique de la fiche.
void main() {
  late HttpServer serveur;
  late int statut;
  late Object corps;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  setUp(() async {
    statut = 200;
    corps = {'ok': true};
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((req) async {
      req.response
        ..statusCode = statut
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(corps));
      await req.response.close();
    });
  });

  tearDown(() => serveur.close(force: true));

  GafesoApi client({String? jeton}) => GafesoApi(
        baseUrl: 'http://127.0.0.1:${serveur.port}',
        tenantSlug: 'zinda',
        token: jeton,
      );

  test('401 sur une route gardée : la session est signalée perdue', () async {
    var signale = 0;
    final api = client(jeton: 'jeton-perime')..onSessionPerdue = () => signale++;
    statut = 401;
    corps = {'message': 'Unauthorized'};

    await expectLater(api.myDocuments(), throwsA(isA<GafesoApiException>()));
    expect(signale, 1);
    api.close();
  });

  test('⚠ 401 SANS jeton : c’est un refus d’identifiants, pas une session perdue',
      () async {
    // La connexion elle-même répond 401 quand le mot de passe est faux. Le
    // confondre avec une expiration renverrait « votre session a expiré » à
    // quelqu'un qui n'a jamais eu de session.
    var signale = 0;
    final api = client()..onSessionPerdue = () => signale++;
    statut = 401;
    corps = {'message': 'Identifiants invalides.'};

    await expectLater(
      api.login(email: 'a@b.c', password: 'faux'),
      throwsA(isA<GafesoApiException>()),
    );
    expect(signale, 0, reason: 'aucune session à perdre');
    api.close();
  });

  test('⚠ membersOnly sur un 200 : traité comme un SIGNAL, pas comme une donnée',
      () async {
    // La fiche est publique : le serveur répond correctement 200 à un visiteur
    // en masquant les champs réservés. Mais nous avons envoyé un jeton — le
    // recevoir prouve que ce jeton ne vaut plus rien.
    var signale = 0;
    final api = client(jeton: 'jeton-perime')..onSessionPerdue = () => signale++;
    statut = 200;
    corps = {
      'id': 'r1',
      'title': 'Droit constitutionnel',
      'items': [],
      'availability': null,
      'digitalCopy': null,
      'membersOnly': true,
    };

    await api.catalogRecord('r1');
    expect(signale, 1);
    api.close();
  });

  test('membersOnly à false : rien n’est signalé', () async {
    var signale = 0;
    final api = client(jeton: 'bon-jeton')..onSessionPerdue = () => signale++;
    statut = 200;
    corps = {'id': 'r1', 'title': 'T', 'items': [], 'membersOnly': false};

    await api.catalogRecord('r1');
    expect(signale, 0);
    api.close();
  });

  test('une réponse saine ne signale jamais rien', () async {
    var signale = 0;
    final api = client(jeton: 'bon-jeton')..onSessionPerdue = () => signale++;
    statut = 200;
    corps = <Map<String, dynamic>>[];

    await api.myDocuments();
    expect(signale, 0);
    api.close();
  });
}
