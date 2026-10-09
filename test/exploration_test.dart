import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/screens/search_screen.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';

/// ⚠ **UN CHAMP VIDE N'EST PAS UNE INVITATION SUFFISANTE.**
///
/// « Que cherchez-vous ? » suppose qu'on sache déjà quoi demander. On vient
/// souvent voir ce qu'il y a. L'écran de recherche montre donc le fonds par
/// domaine — et il le fait sans rafale de requêtes : un étudiant paie ses
/// mégaoctets.
void main() {
  late List<String?> demandes;

  String notice(String id, String titre, String domaine) => jsonEncode({
        'id': id,
        'title': titre,
        'author': 'Traoré, Awa',
        'category': domaine,
        'publishYear': 2024,
      });

  // Enveloppe RÉELLE de l'API : `hits`, `totalHits`, `page`, `totalPages`.
  // (Mon premier jet écrivait `items` ; tout se parsait en page vide, et les
  // carrousels disparaissaient sans qu'aucune erreur ne le dise.)
  String page(List<String> notices) =>
      '{"hits":[${notices.join(',')}],"totalHits":${notices.length},'
      '"page":1,"totalPages":1}';

  Future<Object> explorerFactice(String? category, int limit) async {
    demandes.add(category);
    if (category == null) {
      // L'échantillon : trois domaines, de fréquences différentes.
      return jsonDecode(page([
        notice('1', 'Droit A', 'droit'),
        notice('2', 'Droit B', 'droit'),
        notice('3', 'Médecine A', 'medecine'),
        notice('4', 'Lettres A', 'litterature'),
      ])) as Object;
    }
    return jsonDecode(page([notice('x', 'Titre $category', category)])) as Object;
  }

  setUp(() => demandes = []);

  Future<void> monter(
    WidgetTester t, {
    Future<Object> Function(String?, int)? explorer,
  }) async {
    await t.pumpWidget(MaterialApp(
      theme: gafesoClair(),
      home: SearchScreen(
        search: (q, p, type) async => jsonDecode(page([notice('9', 'Résultat $q', 'droit')])) as Object,
        explorer: explorer,
        openRecord: (_, _) {},
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('le fonds se montre par domaine, sans qu’on tape un mot', (t) async {
    await monter(t, explorer: explorerFactice);
    expect(find.text('Droit'), findsOneWidget);
    expect(find.text('Medecine'), findsOneWidget);
    expect(find.text('Que cherchez-vous ?'), findsNothing);
    // Chaque carrousel porte sa sortie vers la liste complète.
    expect(find.text('Tout voir'), findsWidgets);
  });

  testWidgets('⚠ FRUGALITÉ — ouvrir la recherche ne déclenche pas une rafale',
      (t) async {
    await monter(t, explorer: explorerFactice);
    // Un échantillon, puis quatre domaines au plus. Cinq requêtes, bornées.
    expect(demandes.length, lessThanOrEqualTo(5),
        reason: 'ouvrir la recherche a coûté ${demandes.length} requêtes');
    expect(demandes.first, isNull, reason: 'la première est l’échantillon');
  });

  testWidgets('les carrousels ne se rechargent pas à chaque reconstruction',
      (t) async {
    await monter(t, explorer: explorerFactice);
    final apres = demandes.length;
    await t.pump();
    await t.pumpAndSettle();
    expect(demandes.length, apres, reason: 'des requêtes sont reparties pour rien');
  });

  testWidgets('« Tout voir » bascule sur la recherche filtrée', (t) async {
    await monter(t, explorer: explorerFactice);
    await t.tap(find.text('Tout voir').first);
    await t.pumpAndSettle();
    expect(find.textContaining('Résultat'), findsWidgets);
  });

  group('⚠ quand l’exploration n’est pas possible, on n’affiche pas un trou', () {
    testWidgets('sans explorateur : l’invitation reste', (t) async {
      await monter(t);
      expect(find.text('Que cherchez-vous ?'), findsOneWidget);
    });

    testWidgets('⚠ explorateur en PANNE : l’invitation revient, pas une erreur',
        (t) async {
      // On vient chercher un livre, pas un diagnostic réseau.
      await monter(t, explorer: (_, _) async => throw Exception('réseau coupé'));
      expect(find.text('Que cherchez-vous ?'), findsOneWidget);
      expect(find.textContaining('erreur'), findsNothing);
    });

    testWidgets('un domaine qui échoue ne fait pas tomber les autres', (t) async {
      await monter(t, explorer: (c, l) async {
        demandes.add(c);
        if (c == 'medecine') throw Exception('ce domaine-là seulement');
        return explorerFactice(c, l);
      });
      expect(find.text('Droit'), findsOneWidget);
      expect(find.text('Medecine'), findsNothing);
    });
  });
}
