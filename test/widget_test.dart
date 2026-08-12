// Test de fumée de la coquille : l'app se construit et affiche l'écran lecteur.
// Le lecteur lui-même est une PlatformView native (non rendue hors device) : on
// vérifie seulement l'échafaudage Flutter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/main.dart';

void main() {
  testWidgets('la coquille se construit et affiche le titre du lecteur', (tester) async {
    await tester.pumpWidget(const GafesoApp());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.textContaining('Gafeso'), findsWidgets);
  });
}
