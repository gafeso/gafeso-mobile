import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/widgets/freshness_banner.dart';

void main() {
  final t = DateTime.utc(2026, 8, 9, 12, 0);

  Future<void> monter(WidgetTester tester, Widget w) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: w)));

  testWidgets('donnée fraîche : AUCUN bandeau', (tester) async {
    // Un bandeau permanent devient un décor qu'on ne lit plus, et dilue le
    // signal quand il compte.
    await monter(tester, FreshnessBanner(syncedAt: t, now: t));
    expect(find.byType(Container), findsNothing);
    expect(find.textContaining('Synchronisé'), findsNothing);
  });

  testWidgets('donnée datée : la date est affichée en clair', (tester) async {
    await monter(
      tester,
      FreshnessBanner(syncedAt: t.subtract(const Duration(hours: 9)), now: t),
    );
    expect(find.text('Synchronisé il y a 9 h'), findsOneWidget);
  });

  testWidgets('CARTE (maxAge null) : aucun bandeau même après trois mois',
      (tester) async {
    await monter(
      tester,
      FreshnessBanner(
        syncedAt: t.subtract(const Duration(days: 90)),
        now: t,
        maxAge: null,
      ),
    );
    expect(find.textContaining('Synchronisé'), findsNothing);
  });

  testWidgets('emprunts : 3 h ne datent pas, 9 h datent', (tester) async {
    await monter(tester,
        FreshnessBanner(syncedAt: t.subtract(const Duration(hours: 3)), now: t));
    expect(find.textContaining('Synchronisé'), findsNothing);

    await monter(tester,
        FreshnessBanner(syncedAt: t.subtract(const Duration(hours: 9)), now: t));
    expect(find.textContaining('Synchronisé'), findsOneWidget);
  });

  testWidgets('jamais synchronisé : on dit quoi faire, pas juste « vide »',
      (tester) async {
    await monter(tester, FreshnessBanner(syncedAt: null, now: t));
    expect(find.textContaining('Jamais synchronisé'), findsOneWidget);
    expect(find.textContaining('connectez-vous'), findsOneWidget);
  });

  testWidgets('FRAÎCHE mais mise à jour échouée : le motif est affiché quand même',
      (tester) async {
    // Elle n'est pas « à jour », elle est « à jour à l'instant d'avant ». Au
    // comptoir, la différence compte avant de se fier à un solde de prêts.
    await monter(
      tester,
      FreshnessBanner(syncedAt: t, now: t, lastError: 'Pas de réseau — données de la dernière synchronisation.'),
    );
    expect(find.textContaining('Pas de réseau'), findsOneWidget);
  });

  testWidgets('le bouton Actualiser n’apparaît que s’il y a une action',
      (tester) async {
    await monter(tester, FreshnessBanner(syncedAt: null, now: t));
    expect(find.text('Actualiser'), findsNothing);

    var appels = 0;
    await monter(
      tester,
      FreshnessBanner(syncedAt: null, now: t, onRefresh: () => appels++),
    );
    await tester.tap(find.text('Actualiser'));
    expect(appels, 1);
  });

  testWidgets('EmptyState explique au lieu de laisser blanc', (tester) async {
    await monter(
      tester,
      const EmptyState(
        title: 'Aucun prêt en cours',
        message: 'Empruntez un ouvrage au comptoir : il apparaîtra ici.',
      ),
    );
    expect(find.text('Aucun prêt en cours'), findsOneWidget);
    expect(find.textContaining('au comptoir'), findsOneWidget);
  });
}
