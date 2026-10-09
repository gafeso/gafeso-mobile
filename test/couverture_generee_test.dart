import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';
import 'package:gafeso_mobile/widgets/couverture_generee.dart';

import 'outils_contraste.dart';

/// ⚠ **UNE COUVERTURE DESSINÉE DOIT PORTER DE L'INFORMATION, ET RESTER LISIBLE.**
///
/// Elle remplace l'image sur ce fonds parce que la mesure l'impose : 480 notices
/// sur 480 pointent un SVG non rendu, partagé par quatre-vingts notices à la
/// fois. Ce qui la justifie, c'est donc qu'elle DISTINGUE — et ce qui la rend
/// utilisable, c'est qu'on puisse la lire.
void main() {
  Future<void> poser(
    WidgetTester t,
    Widget c, {
    ThemeData? theme,
  }) async {
    await t.pumpWidget(MaterialApp(
      theme: theme ?? gafesoClair(),
      home: Scaffold(body: Center(child: c)),
    ));
    await t.pump();
  }

  group('ce qu’elle montre', () {
    testWidgets('titre, auteur, type et année', (t) async {
      await poser(
        t,
        const CouvertureGeneree(
          titre: 'Droit foncier rural',
          auteur: 'Congo, Pauline',
          type: 'these',
          annee: 2012,
          domaine: 'droit',
          largeur: 160,
          hauteur: 220,
        ),
      );
      expect(find.text('Droit foncier rural'), findsOneWidget);
      expect(find.text('Congo, Pauline'), findsOneWidget);
      expect(find.text('THESE'), findsOneWidget);
      expect(find.text('2012'), findsOneWidget);
    });

    testWidgets('⚠ un champ ABSENT ne devient pas un tiret ni une valeur plausible',
        (t) async {
      await poser(
        t,
        const CouvertureGeneree(
          titre: 'Sans rien d’autre',
          largeur: 160,
          hauteur: 220,
        ),
      );
      expect(find.text('Sans rien d’autre'), findsOneWidget);
      // Rien d'inventé : ni «—», ni «s.d.», ni «Auteur inconnu».
      expect(find.textContaining('—'), findsNothing);
      expect(find.textContaining('inconnu'), findsNothing);
      expect(find.textContaining('s.d.'), findsNothing);
    });

    testWidgets('en vignette, seule l’initiale — le texte y serait poussière',
        (t) async {
      await poser(
        t,
        const CouvertureGeneree(
          titre: 'Droit foncier rural',
          auteur: 'Congo, Pauline',
          largeur: 44,
          hauteur: 62,
        ),
      );
      expect(find.text('D'), findsOneWidget);
      expect(find.text('Congo, Pauline'), findsNothing);
    });
  });

  group('elle DISTINGUE — c’est sa seule raison d’être', () {
    test('deux domaines différents donnent deux teintes différentes', () {
      // Le fonds mesuré partage 6 images entre 480 notices. Si la couverture
      // dessinée ne distinguait pas davantage, elle ne vaudrait pas la peine.
      // ⚠ Les DIX domaines réellement présents dans le fonds, relevés en base
      // le 09/10/2026 — pas une liste inventée : c'est sur eux que la
      // répartition doit tenir, et c'est elle qui a fait écarter la somme des
      // unités de code (quatre teintes seulement) au profit de FNV-1a.
      const reels = [
        'arts', 'droit', 'economie', 'histoire', 'informatique',
        'langues', 'litterature', 'medecine', 'philosophie', 'sciences',
      ];
      final vues = {for (final d in reels) teinteDomaine(d)};
      expect(vues.length, reels.length,
          reason: 'dix domaines pour ${vues.length} teintes — des champs voisins '
              'se confondraient dans une liste');
    });

    test('⚠ la teinte est STABLE : même domaine, même couleur, toujours', () {
      // Une couverture qui change de couleur au redémarrage détruirait le seul
      // service qu'elle rend : se reconnaître. D'où la somme des unités de code
      // plutôt que `hashCode`, que Dart ne garantit pas stable.
      for (final d in ['droit', 'DROIT', ' Droit ']) {
        expect(teinteDomaine(d), teinteDomaine('droit'));
      }
      expect(teinteDomaine(null), teinteDomaine(''));
    });

    test('un domaine inconnu ne plante pas et rend une teinte de la palette', () {
      // Un établissement qui catalogue autrement garde des couleurs stables,
      // simplement non choisies — c'est le rôle du hachage de repli.
      expect(couverturesDomaine, contains(teinteDomaine('un-domaine-jamais-vu')));
      expect(couverturesDomaine, contains(teinteDomaine(null)));
      expect(teinteDomaine('agronomie-des-sols'), teinteDomaine('agronomie-des-sols'));
    });
  });

  group('⚠ lisible sur TOUTES les teintes', () {
    for (var i = 0; i < couverturesDomaine.length; i++) {
      test('teinte ${i + 1} porte son texte à 4,5:1', () {
        final r = contraste(surCouverture, couverturesDomaine[i]);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${couverturesDomaine[i]} → ${r.toStringAsFixed(2)}:1');
      });
    }

    testWidgets('la couleur RÉELLEMENT peinte du titre tient sur sa teinte',
        (t) async {
      // Les teintes ci-dessus sont celles qu'on DÉCLARE. Ce cas relève celle
      // que l'écran peint — la distinction a déjà coûté un nom de lecteur
      // invisible sur la carte blanche.
      await poser(
        t,
        const CouvertureGeneree(
          titre: 'Épidémiologie de terrain',
          domaine: 'medecine',
          largeur: 160,
          hauteur: 220,
        ),
      );
      final peinte = couleurPeinte(t, 'Épidémiologie de terrain');
      expect(contraste(peinte, teinteDomaine('medecine')), greaterThanOrEqualTo(4.5));
    });
  });
}
