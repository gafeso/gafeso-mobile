import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/session/tenant_code.dart';

void main() {
  group('TenantCode.parse — tous les formats de code d’école', () {
    test('slug nu (et normalisation de casse/espaces)', () {
      expect(TenantCode.parse('zinda'), 'zinda');
      expect(TenantCode.parse('  Zinda '), 'zinda');
      expect(TenantCode.parse('ecole-centrale-2'), 'ecole-centrale-2');
    });

    test('QR d’établissement https://<domaine>/e/<slug> — forme officielle', () {
      expect(TenantCode.parse('https://biblio.ecole.bf/e/zinda'), 'zinda');
      expect(TenantCode.parse('https://biblio.ecole.bf/e/zinda/'), 'zinda');
      expect(TenantCode.parse('HTTPS://Biblio.Ecole.BF/e/Zinda'), 'zinda');
      // Le chemin explicite l'emporte sur l'heuristique du sous-domaine :
      // c'est `droit-l1` qui est imprimé sur l'affiche, pas `zinda`.
      expect(TenantCode.parse('https://zinda.gafeso.bf/e/droit-l1'), 'droit-l1');
    });

    test('origine du descripteur — seules les formes https en portent une', () {
      expect(TenantCode.origin('https://biblio.ecole.bf/e/zinda').toString(),
          'https://biblio.ecole.bf');
      expect(TenantCode.origin('http://localhost:8080/e/zinda').toString(),
          'http://localhost:8080');
      expect(
          TenantCode.descriptorUrl(TenantCode.origin('https://biblio.ecole.bf/e/z')!)
              .toString(),
          'https://biblio.ecole.bf/.well-known/gafeso.json');
      // Slug nu et URI applicatif : aucune origine — ils restent valides quand
      // un serveur est déjà configuré, mais n'en désignent aucun.
      expect(TenantCode.origin('zinda'), isNull);
      expect(TenantCode.origin('gafeso://tenant/zinda'), isNull);
    });

    test('URI applicatif gafeso://tenant/<slug>', () {
      expect(TenantCode.parse('gafeso://tenant/zinda'), 'zinda');
      expect(TenantCode.parse('gafeso://zinda'), 'zinda');
    });

    test('URL d’école : le sous-domaine est le slug', () {
      expect(TenantCode.parse('https://zinda.gafeso.bf'), 'zinda');
      expect(TenantCode.parse('https://zinda.gafeso.bf/opac?x=1'), 'zinda');
    });

    test('paramètre ?tenant= (intention explicite, prioritaire sur l’hôte)', () {
      expect(TenantCode.parse('https://gafeso.bf/app?tenant=zinda'), 'zinda');
      expect(TenantCode.parse('https://autre.gafeso.bf/app?tenant=zinda'), 'zinda');
    });

    test('refuse ce qui n’est pas un slug valide', () {
      expect(TenantCode.parse(''), isNull);
      expect(TenantCode.parse('   '), isNull);
      expect(TenantCode.parse('2zinda'), isNull); // ne commence pas par une lettre
      expect(TenantCode.parse('z'), isNull); // trop court
      expect(TenantCode.parse('Zinda_École'), isNull); // caractères interdits
      expect(TenantCode.parse('https://gafeso.bf'), isNull); // pas de sous-domaine d’école
    });

    test('isValidSlug applique la règle du backend', () {
      expect(TenantCode.isValidSlug('zinda'), isTrue);
      expect(TenantCode.isValidSlug('a' * 49), isTrue);
      expect(TenantCode.isValidSlug('a' * 50), isFalse);
      expect(TenantCode.isValidSlug('-zinda'), isFalse);
    });
  });
}
