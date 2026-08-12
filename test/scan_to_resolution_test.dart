import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/server_discovery.dart';
import 'package:gafeso_mobile/session/tenant_code.dart';

/// CHAÎNE COMPLÈTE : ce que le scanner rend → parseur → résolution du serveur.
///
/// Ce fichier existe à cause d'un défaut trouvé en recette d'appareil, qu'AUCUN
/// test ne pouvait voir : les deux moitiés étaient vertes séparément, et
/// personne ne vérifiait qu'elles se parlaient.
///
/// L'écran de scan rendait le SLUG EXTRAIT (`gafeso-univ`) au lieu de la charge
/// utile (`https://bibliotheque.exemple.bf/e/gafeso-univ`). Le parseur était juste, la
/// résolution était juste — mais la résolution recevait un slug nu, en faisait
/// `https://gafeso-univ`, et l'application annonçait « aucun serveur à cette
/// adresse » sur un QR parfaitement valide. La saisie manuelle marchait, ce qui
/// rendait le diagnostic contre-intuitif.
///
/// Même motif que le PDF factice de la recette de sortie : chaque bout vert,
/// la chaîne cassée.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  // Charge utile EXACTE observée en recette, lue par un scanner tiers sur le QR
  // que /tenancy/qr.png produit.
  const charge = 'https://bibliotheque.exemple.bf/e/gafeso-univ';

  test('RÉGRESSION : la charge utile scannée conserve son ORIGINE', () {
    // C'est la propriété que le bug détruisait. Le slug seul ne suffit pas :
    // sans origine, on ne sait pas à quel serveur parler.
    expect(TenantCode.parse(charge), 'gafeso-univ');
    expect(TenantCode.origin(charge).toString(), 'https://bibliotheque.exemple.bf');
    expect(ServerDiscovery.normalizeOrigin(charge).toString(), 'https://bibliotheque.exemple.bf');
  });

  test('CONTRE-ÉPREUVE : le slug seul ne résout pas — c’était le bug', () {
    // Ce que l'écran de scan rendait avant. `normalizeOrigin` en fait un
    // hôte inexistant : la panne était réelle, pas un malentendu.
    expect(ServerDiscovery.normalizeOrigin('gafeso-univ').toString(),
        'https://gafeso-univ');
    expect(TenantCode.origin('gafeso-univ'), isNull,
        reason: 'un slug nu ne porte aucune origine : rien à interroger');
  });

  test('la charge utile scannée résout jusqu’au descripteur', () async {
    // Serveur local qui répond comme le vrai : /.well-known/gafeso.json.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((req) async {
      if (req.uri.path == '/.well-known/gafeso.json') {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'version': 1,
            'api': 'https://api.bibliotheque.exemple.bf',
            'tenant': 'gafeso-univ',
            'name': 'Université de démonstration',
          }));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    // On rejoue EXACTEMENT ce que fait l'écran serveur avec ce que le scanner
    // lui rend — charge utile brute, jamais pré-mâchée.
    final scanne = 'http://127.0.0.1:${server.port}/e/gafeso-univ';
    final d = ServerDiscovery();
    addTearDown(d.close);

    final cfg = await d.resolve(scanne);

    expect(cfg.apiUrl, 'https://api.bibliotheque.exemple.bf');
    expect(cfg.tenantSlug, 'gafeso-univ');
    expect(cfg.schoolName, 'Université de démonstration');
  });
}
