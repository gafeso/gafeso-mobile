import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/screens/login_screen.dart';
import 'package:gafeso_mobile/screens/tenant_screen.dart';

void main() {
  group('Écran 1 — sélection de l’école', () {
    testWidgets('un code valide est transmis normalisé', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: TenantScreen(onSelected: (s) async => selected.add(s)),
      ));

      await tester.enterText(find.byType(TextField), '  Zinda ');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(selected, ['zinda']);
    });

    testWidgets('un code invalide affiche une erreur et n’appelle rien', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: TenantScreen(onSelected: (s) async => selected.add(s)),
      ));

      await tester.enterText(find.byType(TextField), '2mauvais');
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();

      expect(selected, isEmpty);
      expect(find.textContaining('invalide'), findsOneWidget);
    });

    testWidgets('la charge utile du QR est décodée puis transmise', (tester) async {
      // Le scan caméra est injecté : on teste le CÂBLAGE (charge utile → décodage → sélection),
      // pas la caméra. Le décodage de tous les formats est couvert par tenant_code_test.dart ;
      // l'ouverture réelle de la caméra a été validée sur device.
      final selected = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: TenantScreen(
          onSelected: (s) async => selected.add(s),
          scanner: (_) async => 'gafeso://tenant/zinda',
        ),
      ));

      await tester.tap(find.text('Scanner le QR de l’école'));
      await tester.pumpAndSettle();

      expect(selected, ['zinda']);
    });

    testWidgets('un QR illisible ne déclenche aucune sélection', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: TenantScreen(
          onSelected: (s) async => selected.add(s),
          scanner: (_) async => 'https://exemple.org/rien',
        ),
      ));

      await tester.tap(find.text('Scanner le QR de l’école'));
      await tester.pumpAndSettle();

      expect(selected, isEmpty);
      expect(find.textContaining('invalide'), findsOneWidget);
    });
  });

  group('Écran 2 — connexion', () {
    testWidgets('transmet les identifiants saisis', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(
          tenantSlug: 'zinda',
          onLogin: ({required email, required password}) async {
            calls.add('$email/$password');
            return null;
          },
          onChangeTenant: () async {},
        ),
      ));

      await tester.enterText(find.byType(TextField).first, ' awa@exemple.bf ');
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(calls, ['awa@exemple.bf/secret']); // email trimé, mot de passe intact
    });

    testWidgets('affiche l’erreur renvoyée (ex. 2FA non prise en charge)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(
          tenantSlug: 'zinda',
          onLogin: ({required email, required password}) async =>
              'Double authentification requise',
          onChangeTenant: () async {},
        ),
      ));

      await tester.enterText(find.byType(TextField).first, 'a@b.bf');
      await tester.enterText(find.byType(TextField).last, 'x');
      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Double authentification'), findsOneWidget);
    });

    testWidgets('refuse la soumission si un champ est vide', (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(
        home: LoginScreen(
          tenantSlug: 'zinda',
          onLogin: ({required email, required password}) async {
            called = true;
            return null;
          },
          onChangeTenant: () async {},
        ),
      ));

      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();

      expect(called, isFalse);
      expect(find.textContaining('Renseignez'), findsOneWidget);
    });
  });
}
