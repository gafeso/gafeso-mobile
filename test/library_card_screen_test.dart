import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/cache/offline_cache.dart';
import 'package:gafeso_mobile/screens/library_card_screen.dart';

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

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
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
}
