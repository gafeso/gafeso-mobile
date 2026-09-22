import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/models/catalog.dart';
import 'package:gafeso_mobile/screens/search_screen.dart';

/// Recherche — le seul écran qui exige le réseau.
///
/// Ce qui est vérifié : qu'il le DIT au lieu d'échouer, qu'il ne confond jamais
/// « pas de réseau » avec « aucun résultat », et qu'il ne gaspille pas les
/// données de l'usager.
void main() {
  late int appels;
  late bool horsLigne;
  late List<String> requetes;

  // Charge utile relevée sur /opac/search en fonctionnement.
  String reponse({int total = 2, int page = 1, int totalPages = 1}) => jsonEncode({
        'hits': [
          {
            'id': 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
            'title': 'Droit constitutionnel burkinabè',
            'author': 'Traoré, Awa',
            'category': 'droit',
            'language': 'fr',
            'publishYear': 2023,
            'recordType': 'these',
            'coverUrl': null,
          },
          {
            'id': 'x2',
            'title': 'Précis de droit foncier rural',
            'author': null,
            'category': 'droit',
            'publishYear': 2021,
            'coverUrl': null,
          },
        ],
        'totalHits': total,
        'page': page,
        'totalPages': totalPages,
      });

  setUp(() {
    appels = 0;
    horsLigne = false;
    requetes = [];
  });

  /// Le filtre de type est capté pour pouvoir l'éprouver.
  String? dernierType;

  Future<Object> chercher(String q, int page, String? recordType) async {
    appels++;
    requetes.add(q);
    dernierType = recordType;
    if (horsLigne) throw const SocketException('réseau coupé');
    return jsonDecode(reponse(page: page)) as Object;
  }

  Future<void> monter(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        home: SearchScreen(search: chercher, openRecord: (_, _) {}),
      ));

  testWidgets('état initial : on invite, on ne montre pas « aucun résultat »',
      (tester) async {
    await monter(tester);
    await tester.pump();
    expect(find.text('Que cherchez-vous ?'), findsOneWidget);
    expect(find.text('Aucun résultat'), findsNothing);
  });

  testWidgets('TEMPORISATION : une seule requête pour un mot tapé lettre à lettre',
      (tester) async {
    // Une requête par frappe multiplierait la facture de données par la
    // longueur du mot — ce n'est pas un détail là où les données se paient.
    await monter(tester);
    for (final s in ['d', 'dr', 'dro', 'droi', 'droit']) {
      await tester.enterText(find.byType(TextField), s);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(appels, 0, reason: 'rien ne doit partir pendant la frappe');

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(appels, 1);
    expect(requetes.single, 'droit');
  });

  testWidgets('affiche les résultats', (tester) async {
    await monter(tester);
    await tester.enterText(find.byType(TextField), 'droit');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget);
    expect(find.text('Traoré, Awa · 2023'), findsOneWidget);
    // Auteur absent : pas de séparateur orphelin.
    expect(find.text('2021'), findsOneWidget);
  });

  testWidgets('HORS LIGNE : on dit que le réseau manque, jamais « aucun résultat »',
      (tester) async {
    horsLigne = true;
    await monter(tester);
    await tester.enterText(find.byType(TextField), 'droit');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('La recherche a besoin du réseau'), findsOneWidget);
    expect(find.text('Aucun résultat'), findsNothing,
        reason: '« aucun résultat » ferait conclure que la bibliothèque n’a pas l’ouvrage');
    // Et on rappelle ce qui reste possible sans réseau.
    expect(find.textContaining('hors connexion'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('réessayer relance la MÊME requête', (tester) async {
    horsLigne = true;
    await monter(tester);
    await tester.enterText(find.byType(TextField), 'droit');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    horsLigne = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();

    expect(requetes.last, 'droit');
    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget);
  });

  testWidgets('aucun résultat : on le distingue et on suggère quoi faire',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        search: (q, p, t) async =>
            jsonDecode('{"hits":[],"totalHits":0,"page":1,"totalPages":1}') as Object,
        openRecord: (_, _) {},
      ),
    ));
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Aucun résultat'), findsOneWidget);
    // Ciblé sur le MESSAGE : `textContaining('zzzz')` matchait aussi le champ
    // de saisie, et l'assertion aurait pu passer sans que le message existe.
    expect(find.textContaining('Aucun document ne correspond'), findsOneWidget);
  });

  testWidgets('vider le champ efface les résultats sans appeler le réseau',
      (tester) async {
    await monter(tester);
    await tester.enterText(find.byType(TextField), 'droit');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final avant = appels;

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(appels, avant, reason: 'une requête vide ne doit rien coûter');
    expect(find.text('Que cherchez-vous ?'), findsOneWidget);
  });

  test('SearchPage.merge ajoute la page suivante sans remplacer', () {
    final p1 = SearchPage.fromJson(jsonDecode(reponse(total: 4, page: 1, totalPages: 2)) as Object);
    final p2 = SearchPage.fromJson(jsonDecode(reponse(total: 4, page: 2, totalPages: 2)) as Object);
    final f = p1.merge(p2);
    expect(f.hits.length, 4);
    expect(f.page, 2);
    expect(f.hasMore, isFalse);
  });

  group('filtre par nature de document', () {
    testWidgets('⚠ le type choisi est transmis au serveur', (tester) async {
      // L'API accepte recordType ; l'app n'envoyait que la requête.
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(search: chercher, openRecord: (_, _) {}),
      ));
      await tester.enterText(find.byType(TextField), 'droit');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(dernierType, isNull, reason: 'aucun filtre au départ');

      await tester.tap(find.text('Thèses'));
      await tester.pumpAndSettle();
      expect(dernierType, 'these');
    });

    testWidgets('⚠ un filtre SEUL interroge, sans qu’on tape quoi que ce soit',
        (tester) async {
      // « Montre-moi les thèses » est une demande complète : c'est ce qui
      // permet de PARCOURIR le fonds au lieu de devoir deviner un mot.
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(search: chercher, openRecord: (_, _) {}),
      ));
      final avant = appels;

      await tester.tap(find.text('Mémoires'));
      await tester.pumpAndSettle();

      expect(appels, greaterThan(avant));
      expect(dernierType, 'memoire');
      expect(requetes.last, '');
    });

    testWidgets('revenir à « Tout » relance la MÊME requête sans filtre',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(search: chercher, openRecord: (_, _) {}),
      ));
      await tester.enterText(find.byType(TextField), 'droit');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ouvrages'));
      await tester.pumpAndSettle();
      expect(dernierType, 'ouvrage');

      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      expect(dernierType, isNull);
      expect(requetes.last, 'droit', reason: 'la requête est conservée');
    });

    testWidgets('⚠ « Tout » sans requête n’interroge pas : il n’y a rien à chercher',
        (tester) async {
      // Le comportement juste, et il se teste : un écran vide n'appelle pas le
      // serveur pour rien — un étudiant en 3G paie ses données.
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(search: chercher, openRecord: (_, _) {}),
      ));
      await tester.tap(find.text('Ouvrages'));
      await tester.pumpAndSettle();
      final apresFiltre = appels;

      await tester.tap(find.text('Tout'));
      await tester.pumpAndSettle();
      expect(appels, apresFiltre, reason: 'aucun appel : ni texte ni filtre');
    });
  });

}
