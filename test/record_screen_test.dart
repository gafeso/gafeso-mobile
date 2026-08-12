import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/screens/record_screen.dart';

/// Fiche notice — point de jonction entre la recherche et la lecture hors ligne.
void main() {
  late bool horsLigne;
  late String noticeJson;
  late List<String> reservations;
  late RenewResult reponseReservation;

  // Structure relevée sur GET /opac/records/:id en fonctionnement.
  String notice({
    List<Map<String, dynamic>> items = const [],
    bool digital = false,
  }) =>
      jsonEncode({
        'id': 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
        'title': 'Droit constitutionnel burkinabè',
        'author': 'Traoré, Awa',
        'summary': 'Un précis de droit constitutionnel.',
        'publisher': 'Presses universitaires',
        'publishYear': 2023,
        'category': 'droit',
        'items': items,
        'digitalCopy': digital ? {'id': 'd1', 'format': 'PDF'} : null,
      });

  Map<String, dynamic> exemplaire(String statut) => {
        'barcode': 'BIB-000123',
        'status': statut,
        'location': 'Salle de lecture',
        'callNumber': '342.5 TRA',
      };

  setUp(() {
    horsLigne = false;
    reservations = [];
    reponseReservation = RenewResult(ok: true);
    noticeJson = notice(items: [exemplaire('AVAILABLE')]);
  });

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        recordId: 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
        titleHint: 'Droit constitutionnel burkinabè',
        fetchRecord: (id) async {
          if (horsLigne) throw const SocketException('réseau coupé');
          return jsonDecode(noticeJson) as Object;
        },
        placeHold: (id) async {
          reservations.add(id);
          return reponseReservation;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche les métadonnées et l’état des exemplaires', (tester) async {
    await monter(tester);
    expect(find.text('Traoré, Awa'), findsOneWidget);
    expect(find.text('Presses universitaires · 2023 · droit'), findsOneWidget);
    // « AVAILABLE » ne dit rien à un étudiant.
    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('Salle de lecture · 342.5 TRA'), findsOneWidget);
  });

  testWidgets('DISPONIBLE : on n’offre pas de réserver', (tester) async {
    // Envoyer attendre quelqu'un qui peut emprunter tout de suite serait absurde.
    await monter(tester);
    expect(find.text('Disponible au comptoir'), findsOneWidget);
    expect(find.text('Réserver'), findsNothing);
  });

  testWidgets('TOUT EN PRÊT : on propose de réserver', (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')]);
    await monter(tester);
    expect(find.text('En prêt'), findsOneWidget);
    expect(find.text('Réserver'), findsOneWidget);

    await tester.tap(find.text('Réserver'));
    await tester.pumpAndSettle();
    expect(reservations.single, 'bdefba53-70ee-4214-b83f-a4cc7f6bde75');
  });

  testWidgets('refus de réservation : le MOTIF du serveur est affiché', (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')]);
    reponseReservation = RenewResult(ok: false, reason: 'Vous avez déjà réservé ce document.');
    await monter(tester);

    await tester.tap(find.text('Réserver'));
    await tester.pumpAndSettle();

    expect(find.text('Vous avez déjà réservé ce document.'), findsOneWidget,
        reason: '« échec » ne dirait pas à l’usager quoi faire');
  });

  testWidgets('sans exemplaire physique : ni réservation, ni faux espoir', (tester) async {
    noticeJson = notice(items: const []);
    await monter(tester);
    expect(find.textContaining('Aucun exemplaire physique'), findsOneWidget);
    expect(find.text('Réserver'), findsNothing);
    expect(find.text('Disponible au comptoir'), findsNothing);
  });

  testWidgets('document numérique : le lien vers la lecture hors ligne apparaît',
      (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')], digital: true);
    await monter(tester);
    expect(find.text('Document numérique disponible'), findsOneWidget);
    expect(find.textContaining('hors connexion'), findsOneWidget);
  });

  testWidgets('un statut INCONNU est affiché tel quel, jamais réinterprété',
      (tester) async {
    // Traduire un code inconnu en « indisponible » inventerait une
    // signification ; montrer le code laisse au moins une piste.
    noticeJson = notice(items: [exemplaire('EN_RELIURE')]);
    await monter(tester);
    expect(find.text('EN_RELIURE'), findsOneWidget);
  });

  testWidgets('HORS LIGNE : on l’annonce, on ne prétend pas que la notice n’existe pas',
      (tester) async {
    horsLigne = true;
    await monter(tester);
    expect(find.text('Fiche indisponible hors connexion'), findsOneWidget);
    expect(find.textContaining('étagère'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('le titre connu s’affiche AVANT la réponse du serveur', (tester) async {
    // Une barre de progression anonyme laisse douter d'avoir ouvert la bonne
    // notice. Le titre vient de la liste de résultats, il est déjà connu.
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        recordId: 'r1',
        titleHint: 'Droit constitutionnel burkinabè',
        fetchRecord: (id) => Future.delayed(const Duration(seconds: 5), () => <String, dynamic>{}),
        placeHold: (id) async => RenewResult(ok: true),
      ),
    ));
    await tester.pump();
    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Laisse la minuterie s'achever proprement.
    await tester.pump(const Duration(seconds: 6));
  });
}
