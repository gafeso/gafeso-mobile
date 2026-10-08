import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/screens/a_propos_screen.dart';

/// **Quelle variante est installée sur CE téléphone ?**
///
/// Les deux variantes portaient le même numéro : une capture qui passe ne
/// distinguait pas un défaut du build construit exprès pour l'autoriser. L'app
/// doit répondre elle-même, sans câble et sans outil.
void main() {
  Future<void> ouvrir(WidgetTester t, Map<Object?, Object?>? infos) async {
    await t.pumpWidget(MaterialApp(home: AProposScreen(infos: () async => infos)));
    await t.pumpAndSettle();
  }

  testWidgets('variante CAPTURES : l’app le dit en clair, et dit de ne pas la distribuer',
      (t) async {
    await ouvrir(t, {
      'versionName': '1.0.0-rc1+CAPTURES-NON-DISTRIBUABLE',
      'versionCode': 1,
      'debug': true,
      'capturesAutorisees': true,
    });
    expect(find.text('Capture d’écran AUTORISÉE'), findsOneWidget);
    expect(find.textContaining('NE DOIT PAS être distribuée'), findsOneWidget);
    // Le nom de version porte l'avertissement jusque dans le gestionnaire
    // d'applications, là où l'écran « À propos » n'est pas ouvert.
    expect(find.text('1.0.0-rc1+CAPTURES-NON-DISTRIBUABLE'), findsOneWidget);
    expect(find.textContaining('bloquée'), findsNothing);
  });

  testWidgets('variante NORMALE : capture bloquée, et rien d’alarmant', (t) async {
    await ouvrir(t, {
      'versionName': '1.0.0-rc1',
      'versionCode': 1,
      'debug': false,
      'capturesAutorisees': false,
    });
    expect(find.text('Capture d’écran bloquée — version normale.'), findsOneWidget);
    expect(find.text('1.0.0-rc1'), findsOneWidget);
    expect(find.text('publication'), findsOneWidget);
    expect(find.text('Capture d’écran AUTORISÉE'), findsNothing);
  });

  testWidgets('⚠ canal absent : on ne PRÉTEND pas que la capture est bloquée', (t) async {
    // Le pire écran possible serait un écran rassurant par défaut : il dirait
    // « protégé » sans rien savoir. On dit qu'on ne sait pas.
    await ouvrir(t, null);
    expect(find.text('Informations de version indisponibles.'), findsOneWidget);
    expect(find.textContaining('bloquée'), findsNothing);
    expect(find.text('Capture d’écran AUTORISÉE'), findsNothing);
  });
}
