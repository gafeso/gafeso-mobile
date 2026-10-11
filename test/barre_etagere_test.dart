import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/app_state.dart';
import 'package:gafeso_mobile/screens/shelf_screen.dart';
import 'package:gafeso_mobile/session/session.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';

/// ⚠ **LE TITRE DE L'ÉTAGÈRE DOIT TENIR EN ENTIER SUR 360 dp.**
///
/// 360 dp est la largeur de référence Android, celle des téléphones d'entrée de
/// gamme qui forment l'essentiel du parc visé. Six actions dans la barre n'y
/// laissaient au titre que « Mon … » : un écran dont on ne lit plus le nom ne se
/// situe plus, et c'est la première information de la barre.
///
/// Ce test ne regarde PAS le nombre d'icônes — on pourrait en remettre une de
/// taille différente et passer quand même. Il regarde ce qui compte : le texte
/// est-il tronqué, oui ou non.
void main() {
  late Map<String, String> coffre;
  late Directory tmp;

  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gafeso-barre-');
    coffre = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
      switch (call.method) {
        case 'put':
          coffre[call.arguments['name'] as String] = call.arguments['value'] as String;
          return true;
        case 'get':
          return coffre[call.arguments['name'] as String];
        case 'remove':
          coffre.remove(call.arguments['name'] as String);
          return true;
        case 'clear':
          coffre.clear();
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<AppState> etatConnecte() async {
    coffre['tenant'] = 'zinda';
    coffre['session'] = jsonEncode(const AppSession(
      tenantSlug: 'zinda',
      token: 'jeton',
      userId: 'u-1',
      displayName: 'Awa',
    ).toJson());
    // Adresse injoignable : l'écran bascule en mode hors ligne, ce qui est
    // exactement l'état où le titre doit rester lisible.
    final s = AppState(
      apiBaseUrl: 'http://127.0.0.1:1',
      storageDir: tmp,
      sessionStore: SessionStore(),
    );
    await s.restore();
    return s;
  }

  /// Monte l'étagère sur un écran de 360 × 640 dp.
  Future<void> monter(WidgetTester t, AppState s) async {
    await t.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: gafesoClair(),
      home: ShelfScreen(state: s),
    ));
    await t.pump(const Duration(milliseconds: 100));
  }

  /// Facteur de réduction réellement appliqué au titre.
  ///
  /// ⚠ `didExceedMaxLines` ne suffit PLUS depuis que le titre passe par un
  /// `FittedBox` : à l'intérieur, le paragraphe est mesuré sans contrainte et
  /// n'est donc JAMAIS tronqué — l'assertion serait vraie quoi qu'il arrive.
  /// Ce qui reste à tenir, c'est que le titre entier reste LISIBLE : on compare
  /// la largeur peinte à la largeur demandée par le texte.
  double reductionDuTitre(WidgetTester t, String titre) {
    final peint = t.getSize(find.ancestor(
      of: find.text(titre),
      matching: find.byType(FittedBox),
    ).first);
    final demande = t.renderObject<RenderParagraph>(find.text(titre))
        .getMaxIntrinsicWidth(double.infinity);
    return peint.width / demande;
  }

  /// Taille effective du titre, en points — la grandeur qui décide vraiment
  /// s'il se lit, et non le rapport de réduction.
  ///
  /// ⚠ LE PREMIER JET POSAIT UN PLANCHER EN RATIO (0,8), et c'était une
  /// estimation déguisée en mesure : 0,8 de quoi ? Le jour où la maquette a
  /// demandé une troisième action dans la barre, le titre est tombé à 76 % —
  /// soit 16,7 sp, parfaitement lisibles — et le test a crié pour un chiffre
  /// qui ne désignait rien.
  ///
  /// On mesure donc ce qui compte : la taille réellement affichée.
  double tailleEffective(WidgetTester t, String titre) {
    final declaree = t
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().contains(titre))
        .text
        .style!
        .fontSize!;
    return declaree * reductionDuTitre(t, titre);
  }

  /// ⚠ 15 points : en deçà, un titre de barre cesse de se lire comme un titre
  /// et passe pour une légende. C'est la limite basse des styles de corps de
  /// Material, pas un chiffre choisi pour faire passer le test.
  const plancherPoints = 15.0;

  RenderParagraph paragrapheDuTitre(WidgetTester t, String titre) =>
      t.renderObject<RenderParagraph>(find.descendant(
        of: find.byType(AppBar),
        matching: find.text(titre),
      ));

  group('le titre tient en entier sur 360 dp', () {
    testWidgets('« Mon étagère » n’est pas tronqué', (t) async {
      final s = await etatConnecte();
      await monter(t, s);
      expect(find.text('Mon étagère'), findsOneWidget);
      expect(paragrapheDuTitre(t, 'Mon étagère').didExceedMaxLines, isFalse,
          reason: 'le titre est rogné');
      final pt = tailleEffective(t, 'Mon étagère');
      expect(pt, greaterThanOrEqualTo(plancherPoints),
          reason: 'affiché à ${pt.toStringAsFixed(1)} pt — trop petit pour un titre');
    });

    testWidgets('⚠ sans circulation, le titre long tient AUSSI', (t) async {
      // Le titre le plus LONG que l'app affiche. C'est lui qui contraint la
      // barre, pas le plus court — et c'est celui d'une bibliothèque numérique,
      // donc d'exactement le profil que l'Université Virtuelle présente.
      final s = await etatConnecte();
      s.circulationInactive();
      await monter(t, s);
      expect(find.text('Documents'), findsOneWidget);
      expect(paragrapheDuTitre(t, 'Documents').didExceedMaxLines, isFalse);
      final pt = tailleEffective(t, 'Documents');
      expect(pt, greaterThanOrEqualTo(plancherPoints),
          reason: 'affiché à ${pt.toStringAsFixed(1)} pt — trop petit pour un titre');
    });
  });

  group('⚠ TÉMOIN NÉGATIF — l’assertion sait détecter une troncature', () {
    testWidgets('un titre volontairement interminable TOMBE sous le plancher',
        (t) async {
      // Sans ce cas, la mesure de réduction pourrait valoir 1,0 pour une raison
      // sans rapport (titre absent, FittedBox non trouvé) et les deux cas
      // ci-dessus applaudiraient une barre illisible.
      await t.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        theme: gafesoClair(),
        home: Scaffold(
          appBar: AppBar(
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('Un titre délibérément interminable qui ne peut pas tenir'),
            ),
            actions: const [
              Icon(Icons.grid_view_outlined),
              Icon(Icons.search),
              Icon(Icons.more_vert),
            ],
          ),
        ),
      ));
      const long = 'Un titre délibérément interminable qui ne peut pas tenir';
      expect(tailleEffective(t, long), lessThan(plancherPoints));
    });
  });

  group('ce que la barre et le menu portent', () {
    testWidgets('la barre ne garde que les gestes répétés', (t) async {
      final s = await etatConnecte();
      await monter(t, s);
      expect(find.widgetWithIcon(IconButton, Icons.search), findsOneWidget);
      // La bascule d'affichage, demandée dans la barre par la maquette.
      expect(find.widgetWithIcon(IconButton, Icons.view_list_outlined), findsOneWidget);
      // Tout le reste est descendu dans le menu : plus d'icône à deviner.
      expect(find.widgetWithIcon(IconButton, Icons.refresh), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.badge_outlined), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.info_outline), findsNothing);
      // TROIS boutons : la bascule grille/liste, la recherche, et celui que le
      // menu porte lui-même. ⚠ C'est le budget MAXIMAL : le titre s'affiche
      // alors à 16,7 pt au lieu de 22, et une quatrième action le ferait
      // passer sous les 15 pt.
      expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)),
          findsNWidgets(3));
    });

    testWidgets('le menu nomme les destinations, et respecte la circulation',
        (t) async {
      final s = await etatConnecte();
      await monter(t, s);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(find.text('Actualiser'), findsOneWidget);
      expect(find.text('Ma carte de lecteur'), findsOneWidget);
      expect(find.text('Mes prêts et réservations'), findsOneWidget);
      expect(find.text('À propos'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
    });

    testWidgets('⚠ sans circulation, le menu ne propose NI carte NI prêts',
        (t) async {
      final s = await etatConnecte();
      s.circulationInactive();
      await monter(t, s);
      await t.tap(find.byType(PopupMenuButton<String>));
      await t.pumpAndSettle();
      expect(find.text('Ma carte de lecteur'), findsNothing);
      expect(find.text('Mes prêts et réservations'), findsNothing);
      // ...mais le reste du menu demeure : on retire une promesse, pas le menu.
      expect(find.text('Actualiser'), findsOneWidget);
      expect(find.text('À propos'), findsOneWidget);
      expect(find.text('Se déconnecter'), findsOneWidget);
    });
  });
}
