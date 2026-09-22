import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';

/// Client HTTP de l'espace lecteur.
///
/// Le premier test existe pour une raison précise : en écrivant ce client j'ai
/// produit `'/reader/loans/\$checkoutId/renew'` — un dollar ÉCHAPPÉ, donc une
/// chaîne littérale sans interpolation. `flutter analyze` n'y voit rien, le
/// code compile, et l'application aurait appelé une URL contenant le texte
/// « $checkoutId ». Le serveur aurait répondu 404, et le message affiché aurait
/// été « prêt introuvable » — accusant les données plutôt que l'URL.
/// Seul un test qui REGARDE le chemin réellement demandé l'attrape.
void main() {
  late HttpServer server;
  late List<String> chemins;
  late int statut;
  late Object corps;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  setUp(() async {
    chemins = [];
    statut = 200;
    corps = {'ok': true};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      chemins.add(req.uri.path);
      req.response
        ..statusCode = statut
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(corps));
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  GafesoApi api() {
    final a = GafesoApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      tenantSlug: 'zinda',
      token: 'jeton',
    );
    addTearDown(a.close);
    return a;
  }

  test('RÉGRESSION : l’identifiant est bien INTERPOLÉ dans l’URL', () async {
    corps = {'dueDate': '2026-08-23T16:00:00.000Z'};
    await api().renewLoan('cc253f12-c2e3-4738-a563-c32cc0795f76');

    expect(chemins.single, '/reader/loans/cc253f12-c2e3-4738-a563-c32cc0795f76/renew');
    expect(chemins.single, isNot(contains(r'$')),
        reason: 'un dollar littéral signifie que l’interpolation a été perdue');
  });

  test('annulation de réservation : même vérification', () async {
    await api().cancelHold('07f68a00-f811-4a33-b715-3a9432b6a867');
    expect(chemins.single, '/reader/holds/07f68a00-f811-4a33-b715-3a9432b6a867/cancel');
  });

  test('renouvellement accepté : nouvelle échéance rendue', () async {
    corps = {'dueDate': '2026-08-23T16:00:00.000Z'};
    final r = await api().renewLoan('abc');
    expect(r.ok, isTrue);
    expect(r.dueDate?.toUtc(), DateTime.utc(2026, 8, 23, 16));
  });

  test('REFUS MÉTIER : un motif, pas une exception', () async {
    // Le backend refuse pour des raisons distinctes — plafond, retard,
    // réservation d'autrui. Les confondre en « erreur » laisserait l'usager
    // sans recours : selon le motif il doit rendre, attendre, ou ne rien faire.
    statut = 409;
    corps = {'message': 'Document réservé par un autre lecteur.', 'statusCode': 409};
    final r = await api().renewLoan('abc');

    expect(r.ok, isFalse);
    expect(r.reason, 'Document réservé par un autre lecteur.');
  });

  test('une PANNE serveur reste une panne', () async {
    // 5xx n'est pas un refus motivé : le masquer en message métier ferait
    // croire à une règle de bibliothèque là où le serveur est tombé.
    statut = 500;
    corps = {'message': 'Internal server error'};
    await expectLater(api().renewLoan('abc'), throwsA(isA<GafesoApiException>()));
  });

  test('un corps d’erreur non JSON ne remonte pas de HTML à l’écran', () async {
    statut = 403;
    corps = {};
    final r = await api().renewLoan('abc');
    expect(r.ok, isFalse);
    expect(r.reason, 'Renouvellement refusé par la bibliothèque.');
  });

  test('⚠ une RÉSERVATION refusée ne parle pas de renouvellement', () async {
    // Les deux appels partageaient une extraction dont la chute nommait le
    // renouvellement : une réservation sans message serveur annonçait donc un
    // refus de renouvellement, opération que le lecteur n'a pas demandée.
    statut = 403;
    corps = {};
    final r = await api().placeHold('rec-1');
    expect(r.ok, isFalse);
    expect(r.reason, 'Réservation refusée par la bibliothèque.');
  });

  test('une réservation refusée AVEC message remonte celui du serveur', () async {
    statut = 409;
    corps = {'message': 'Vous avez déjà une réservation sur ce titre.'};
    final r = await api().placeHold('rec-1');
    expect(r.ok, isFalse);
    expect(r.reason, 'Vous avez déjà une réservation sur ce titre.');
  });
}
