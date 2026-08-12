import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';

/// Une adresse mal configurée — le SITE au lieu de l'API — renvoie du HTML.
/// Sans garde, l'écran affichait l'exception brute de Dart :
///
///   FormatException: Unexpected character (at character 1) /login ^
///
/// Rencontré pendant la re-validation mobile du 2026-08-03 : c'est
/// exactement ce que verra un informaticien qui saisit l'URL du site.
void main() {
  late HttpServer server;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      // Ce que rend un serveur web quand on frappe une route applicative.
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<!DOCTYPE html><html><body>Redirecting to /login</body></html>');
      await req.response.close();
    });
  });

  tearDownAll(() async => server.close(force: true));

  test('une réponse HTML donne un message compréhensible, pas une FormatException', () async {
    final api = GafesoApi(
      baseUrl: 'http://127.0.0.1:${server.port}',
      tenantSlug: 'zinda',
    );
    addTearDown(api.close);

    try {
      await api.login(email: 'a@b.bf', password: 'x');
      fail('une réponse HTML aurait dû lever une erreur');
    } on GafesoApiException catch (e) {
      // Le message doit ORIENTER : dire que la réponse n'est pas du JSON et
      // pointer la cause probable (l'URL vise le site, pas l'API).
      expect(e.body, contains('autre chose que du JSON'));
      expect(e.body, contains('/api'));
    } on FormatException {
      fail('l’exception brute de Dart ne doit plus remonter jusqu’à l’écran');
    }
  });
}
