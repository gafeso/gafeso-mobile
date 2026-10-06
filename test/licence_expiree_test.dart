import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/session/library_store.dart';

/// LICENCE EXPIRÉE — la date était sur l'appareil et personne ne la regardait.
///
/// Trouvé par un test sur téléphone réel : une installation d'août réinstallée
/// par-dessus. L'étagère annonçait « Disponible hors ligne » pour un bail échu,
/// et le lecteur natif refusait ensuite d'ouvrir. Même motif que la carte verte
/// de la fiche : l'information est là, l'écran la jette, puis il promet ce qui
/// en dépend.
void main() {
  LocalDocument doc({String? expiresAt, String corps = ''}) => LocalDocument(
        docId: 'd1',
        title: 'Droit constitutionnel',
        licenseId: 'lic-1',
        licenseBody: corps.isNotEmpty
            ? corps
            : jsonEncode({
                'v': 1,
                'docId': 'd1',
                'userId': 'u1',
                'tenant': 'zinda',
                'expiresAt': ?expiresAt,
              }),
        signature: 'sig',
        licensePublicKey: 'pk',
        wrappedCek: 'wc',
        blobPath: '/tmp/d1.gafs',
      );

  final maintenant = DateTime.utc(2026, 9, 22, 12);

  group('lecture de la fin de bail', () {
    test('la date est lue du corps de licence local', () {
      final d = doc(expiresAt: '2026-10-05T00:00:00Z');
      expect(d.expiresAt, DateTime.utc(2026, 10, 5));
    });

    test('un bail futur n’est pas expiré', () {
      expect(doc(expiresAt: '2026-10-05T00:00:00Z').estExpiree(maintenant), isFalse);
    });

    test('⚠ un bail échu EST expiré — c’est le cas trouvé sur téléphone', () {
      // Licence d'août, 14 jours de bail : échue depuis fin août.
      expect(doc(expiresAt: '2026-08-25T00:00:00Z').estExpiree(maintenant), isTrue);
    });

    test('⚠ sans date, on n’INVENTE pas d’expiration', () {
      // Le natif seul tranche : il vérifie la signature, pas nous.
      final d = doc();
      expect(d.expiresAt, isNull);
      expect(d.estExpiree(maintenant), isFalse);
    });

    test('un corps illisible ne lève pas : il ne dit rien', () {
      final d = doc(corps: 'ceci n’est pas du JSON');
      expect(d.expiresAt, isNull);
      expect(d.estExpiree(maintenant), isFalse);
    });

    test('une date malformée ne dit rien non plus', () {
      expect(doc(expiresAt: 'demain').expiresAt, isNull);
    });
  });

  group('⚠ expiration ≠ purge — la distinction est gardée', () {
    test('un document expiré reste PRÉSENT dans la bibliothèque locale', () {
      // Le contenu est toujours là ; c'est la licence qui ne vaut plus. Purger
      // sur l'horloge locale laisserait un changement d'heure détruire du
      // contenu — seule une réponse serveur (`revoked`/`expired`) retire.
      final d = doc(expiresAt: '2026-08-25T00:00:00Z');
      expect(d.estExpiree(maintenant), isTrue);
      expect(d.blobPath, isNotEmpty, reason: 'le blob n’est pas effacé');
      expect(d.lastStatus, 'active', reason: 'aucun retrait serveur');
    });

    test('la sérialisation ne perd pas le corps qui porte la date', () {
      final d = doc(expiresAt: '2026-08-25T00:00:00Z');
      final relu = LocalDocument.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(relu.estExpiree(maintenant), isTrue);
    });
  });
}
