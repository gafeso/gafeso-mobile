import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/widgets/cover_image.dart';

/// La couverture ne doit JAMAIS empêcher un écran d'être lisible.
void main() {
  Future<void> monter(WidgetTester t, {String? url, String titre = 'Droit'}) =>
      t.pumpWidget(MaterialApp(
        home: Scaffold(body: CoverImage(coverUrl: url, titre: titre)),
      ));

  testWidgets('sans cache : substitut immédiat, aucune attente', (tester) async {
    await monter(tester, url: 'https://x.exemple.bf/a.png');
    // Pas de pumpAndSettle : l'écran doit être complet dès la première frame.
    expect(find.text('D'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('sans couverture : substitut, pas de trou', (tester) async {
    await monter(tester, url: null, titre: 'Mémoire de droit');
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('⚠ une URL SVG ne tente rien et retombe sur le substitut',
      (tester) async {
    await monter(tester, url: 'https://x.exemple.bf/a.svg', titre: 'Zoologie');
    expect(find.text('Z'), findsOneWidget);
  });

  testWidgets('titre vide : substitut neutre, jamais d’exception', (tester) async {
    await monter(tester, url: null, titre: '   ');
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('l’initiale gère les accents et la casse', (tester) async {
    await monter(tester, url: null, titre: 'économie du Sahel');
    expect(find.text('É'), findsOneWidget);
  });
}
