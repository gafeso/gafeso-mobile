import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/cache/offline_cache.dart';
import 'package:gafeso_mobile/screens/library_card_screen.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';

import 'outils_contraste.dart';

/// Carte de lecteur — l'écran qui doit marcher au comptoir, sans wifi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final coffre = <String, String>{};
  late bool horsLigne;
  late String carteJson;
  late List<double?> luminosites;

  // Charge utile relevée sur GET /reader/card en fonctionnement.
  String carte({String symbology = 'code128'}) => jsonEncode({
        'barcode': 'LEC-C430CE08',
        'category': 'etudiant',
        'symbology': symbology,
        'displayName': 'Awa Traoré',
        'expiryDate': null,
      });

  setUp(() {
    coffre.clear();
    horsLigne = false;
    carteJson = carte();
    luminosites = [];

    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
      final nom = (call.arguments as Map?)?['name'] as String?;
      switch (call.method) {
        case 'get':
          return coffre[nom];
        case 'put':
          coffre[nom!] = (call.arguments as Map)['value'] as String;
          return null;
        case 'remove':
          coffre.remove(nom);
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('com.gafeso/device'), (call) async {
      if (call.method == 'setBrightness') {
        luminosites.add((call.arguments as Map?)?['value'] as double?);
      }
      return null;
    });
  });

  Future<void> monter(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: LibraryCardScreen(
        fetchCard: () async {
          if (horsLigne) throw const SocketException('réseau coupé');
          return jsonDecode(carteJson) as Object;
        },
        cache: OfflineCache(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche le code-barres ET le numéro en clair', (tester) async {
    await monter(tester);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    // Le numéro en clair permet la saisie manuelle si la douchette échoue —
    // écran rayé, mauvaise lumière — plutôt que de renvoyer l'étudiant.
    expect(find.text('LEC-C430CE08'), findsOneWidget);
    expect(find.text('Awa Traoré'), findsOneWidget);
  });

  testWidgets('AUCUN bandeau de fraîcheur, jamais', (tester) async {
    // Douter d'un code-barres immuable, c'est refuser un prêt.
    await monter(tester);
    expect(find.textContaining('Synchronisé'), findsNothing);
    expect(find.textContaining('Jamais synchronisé'), findsNothing);
  });

  testWidgets('HORS LIGNE après une synchro : la carte reste affichée',
      (tester) async {
    await monter(tester); // première synchro : mise en cache
    expect(find.text('LEC-C430CE08'), findsOneWidget);

    horsLigne = true;
    await monter(tester); // relance sans réseau

    expect(find.byType(BarcodeWidget), findsOneWidget,
        reason: 'c’est le cas d’usage : le comptoir n’a pas de wifi');
    expect(find.text('LEC-C430CE08'), findsOneWidget);
  });

  testWidgets('jamais synchronisée et hors ligne : on explique, pas d’écran vide',
      (tester) async {
    horsLigne = true;
    await monter(tester);
    expect(find.text('Carte pas encore disponible'), findsOneWidget);
    expect(find.textContaining('hors connexion'), findsOneWidget);
  });

  testWidgets('symbologie INCONNUE : pas de code-barres muet', (tester) async {
    // Dessiner du Code 128 « au cas où » produirait une carte d'apparence
    // normale que la douchette ne lit pas — l'échec le plus coûteux, celui
    // qui ne dit pas son nom.
    carteJson = carte(symbology: 'ean13');
    await monter(tester);

    expect(find.byType(BarcodeWidget), findsNothing);
    expect(find.textContaining('ean13'), findsOneWidget);
    expect(find.text('LEC-C430CE08'), findsOneWidget,
        reason: 'le numéro reste saisissable à la main');
  });

  testWidgets('luminosité poussée à l’ouverture, restaurée à la sortie',
      (tester) async {
    await monter(tester);
    expect(luminosites.first, 1.0);

    // On quitte l'écran.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    expect(luminosites.last, isNull,
        reason: 'laisser l’écran à fond viderait la batterie');
  });

  /// ⚠ **LA CARTE RESTE BLANCHE EN MODE SOMBRE — SON TEXTE AUSSI DOIT SUIVRE.**
  ///
  /// Le fond blanc est FONCTIONNEL : une douchette lit un code-barres sur du
  /// blanc. Mais les textes sans couleur déclarée héritaient d'`onSurface`,
  /// clair en mode sombre, et devenaient quasi invisibles sur ce blanc. Le
  /// défaut est muet — l'écran s'affiche, le code se lit, et c'est le NOM qu'on
  /// présente au comptoir qui a disparu. Trouvé sur capture, pas en relecture.
  group('⚠ lisibilité de la carte en mode sombre', () {
    for (final (nom, theme) in [('clair', gafesoClair()), ('sombre', gafesoSombre())]) {
      testWidgets('[$nom] le NOM du lecteur se lit sur la carte', (t) async {
        await monter(t, theme: theme);
        final fond = theme.extension<GafesoPalette>()!.carte;
        final r = contraste(couleurPeinte(t, 'Awa Traoré'), fond);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: 'nom à ${r.toStringAsFixed(2)}:1 sur la carte');
      });

      testWidgets('[$nom] le NUMÉRO en clair se lit aussi', (t) async {
        await monter(t, theme: theme);
        final fond = theme.extension<GafesoPalette>()!.carte;
        final r = contraste(couleurPeinte(t, 'LEC-C430CE08'), fond);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: 'numéro à ${r.toStringAsFixed(2)}:1 sur la carte');
      });
    }

    testWidgets('⚠ TÉMOIN — sans le style de carte, le sombre échouerait', (t) async {
      // Ce que faisait l'écran avant le correctif : hériter d'`onSurface`.
      // On vérifie que cette couleur-là, sur le blanc de la carte, est bien
      // refusée — sinon l'assertion ci-dessus ne garantit rien.
      final sombre = gafesoSombre();
      final r = contraste(
        sombre.colorScheme.onSurface,
        sombre.extension<GafesoPalette>()!.carte,
      );
      expect(r, lessThan(4.5));
    });
  });
}
