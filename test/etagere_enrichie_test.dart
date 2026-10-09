import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';

/// ⚠ **L'ÉTAGÈRE SAIT ENFIN DE QUOI ELLE PARLE.**
///
/// `GET /offline/my-documents` ne rendait que `{docId, title, fileFormat}` :
/// l'app recopiait auteur, domaine et année sur l'appareil au téléchargement,
/// faute de quoi elle n'aurait pu composer que des couvertures au titre seul.
/// Depuis le backend rc8, la route les porte.
///
/// Relevé avant d'y toucher, sur l'instance de dev : **127 documents sur 127**
/// portent les trois champs, aucun vide.
void main() {
  group('la charge enrichie est lue', () {
    test('auteur, domaine et année arrivent de la route', () {
      // Charge RÉELLE, relevée le 09/10/2026 sur `/offline/my-documents`.
      final d = ShelfDocument.fromJson(jsonDecode('''
        {"docId":"a1","title":"Textiles et motifs en Afrique de l’Ouest",
         "fileFormat":"PDF","auteur":"Ouoba, Justine","domaine":"arts","annee":2025}
      ''') as Map<String, dynamic>);
      expect(d.auteur, 'Ouoba, Justine');
      expect(d.domaine, 'arts');
      expect(d.annee, 2025);
    });

    test('⚠ une charge ANCIENNE reste lisible — serveur antérieur à rc8', () {
      // Un établissement peut tourner sur une version plus ancienne. Trois
      // champs manquants ne doivent pas faire tomber l'étagère entière.
      final d = ShelfDocument.fromJson(
        jsonDecode('{"docId":"a1","title":"Un titre","fileFormat":"PDF"}')
            as Map<String, dynamic>,
      );
      expect(d.title, 'Un titre');
      expect(d.auteur, isNull);
      expect(d.domaine, isNull);
      expect(d.annee, isNull);
    });

    test('⚠ un champ VIDE n’est pas un champ rempli', () {
      // `annee: null` et `auteur: ""` existent dans les fonds réels d'autres
      // établissements : on ne les transforme pas en valeur plausible.
      final d = ShelfDocument.fromJson(
        jsonDecode('{"docId":"a1","title":"T","fileFormat":"PDF","auteur":null,"annee":null}')
            as Map<String, dynamic>,
      );
      expect(d.auteur, isNull);
      expect(d.annee, isNull);
    });
  });
}
