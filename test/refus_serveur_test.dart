import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';

/// LE REFUS DU SERVEUR ARRIVE-T-IL AU LECTEUR ?
///
/// Le produit rédige des refus précis, et chacun appelle une conduite
/// différente : se ré-enrôler, demander un droit, attendre une préparation.
/// L'étagère les remplaçait par une phrase unique pour les 403 et par un
/// NUMÉRO pour tout le reste — en jetant le seul texte utilisable.
///
/// Les corps ci-dessous sont ceux que `offline-licenses.service.ts` produit
/// réellement (NestJS sérialise `message`, `error`, `statusCode`).
void main() {
  GafesoApiException refus(int code, String message) => GafesoApiException(
        code,
        '{"message":"$message","error":"Forbidden","statusCode":$code}',
        '/offline/licenses',
      );

  const chute = 'Téléchargement refusé (403).';

  group('les refus réels du serveur traversent l’app intacts', () {
    test('appareil révoqué : ce n’est PAS un défaut de droit', () {
      // Le lecteur a le droit ; c'est son appareil qui est hors jeu. L'ancienne
      // phrase unique (« Vous n'avez pas (ou plus) accès ») l'envoyait demander
      // un droit qu'il possède déjà.
      final e = refus(403, 'Appareil inconnu ou révoqué.');
      expect(e.motif(defaut: chute), 'Appareil inconnu ou révoqué.');
    });

    test('droit manquant : le seul cas que l’ancienne phrase couvrait', () {
      final e = refus(403, 'Vous n’avez pas accès à ce document.');
      expect(e.motif(defaut: chute), 'Vous n’avez pas accès à ce document.');
    });

    test('licence révoquée : le bail a été retiré, ce n’est pas un refus d’accès', () {
      final e = refus(403, 'Licence revoked : téléchargement refusé.');
      expect(e.motif(defaut: chute), 'Licence revoked : téléchargement refusé.');
    });

    test('⚠ document non préparé : un 400, donc un NUMÉRO NU avant ce lot', () {
      // C'est le cas le plus fréquent du fonds mesuré (154 documents sur 155) :
      // l'app affichait « Téléchargement impossible (400). » alors que le
      // serveur disait quoi faire — attendre la préparation.
      final e = refus(400, 'Document pas encore préparé pour la lecture hors-ligne.');
      expect(
        e.motif(defaut: 'Téléchargement refusé (400).'),
        'Document pas encore préparé pour la lecture hors-ligne.',
      );
    });

    test('aucun exemplaire numérique : un 404, également nu avant ce lot', () {
      final e = refus(404, 'Aucun exemplaire numérique pour ce document.');
      expect(
        e.motif(defaut: 'Téléchargement refusé (404).'),
        'Aucun exemplaire numérique pour ce document.',
      );
    });
  });

  group('la chute ne sert que si le serveur n’a rien rédigé', () {
    test('corps non JSON : jamais de HTML brut à l’écran', () {
      final e = GafesoApiException(502, '<html><body>Bad Gateway</body></html>', '/x');
      expect(e.motif(defaut: 'Indisponible.'), 'Indisponible.');
    });

    test('corps JSON sans message', () {
      final e = GafesoApiException(403, '{"statusCode":403}', '/x');
      expect(e.motif(defaut: chute), chute);
    });

    test('message vide : traité comme absent', () {
      final e = GafesoApiException(403, '{"message":""}', '/x');
      expect(e.motif(defaut: chute), chute);
    });

    test('liste de validations : NestJS en rend plusieurs, on les joint', () {
      final e = GafesoApiException(
        400,
        '{"message":["docId doit être un UUID","deviceId requis"]}',
        '/x',
      );
      expect(
        e.motif(defaut: chute),
        'docId doit être un UUID · deviceId requis',
      );
    });
  });
}
