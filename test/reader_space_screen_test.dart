import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/cache/offline_cache.dart';
import 'package:gafeso_mobile/screens/reader_space_screen.dart';

/// Écran « Mon espace » — le premier consommateur du socle hors ligne.
///
/// Ce qui est vérifié ici n'est pas la mise en page : c'est que l'écran RESTE
/// UTILISABLE quand le réseau tombe, et qu'il ne confond jamais deux états qui
/// se ressemblent (« aucun prêt » et « pas de carte »).
void main() {
  late String pretsJson;
  late String resaJson;
  late bool horsLigne;

  final coffre = <String, String>{};
  final t = DateTime.utc(2026, 8, 14, 10, 0);

  setUp(() async {
    coffre.clear();
    horsLigne = false;
    pretsJson = jsonEncode({
      'hasCard': true,
      'current': [
        {
          'checkoutId': 'c1',
          'recordId': 'r1',
          'title': 'Droit constitutionnel burkinabè',
          'itemBarcode': 'BIB-000123',
          'dueDate': '2026-08-16T16:00:00.000Z',
          'renewals': 0,
          'overdue': false,
          'overdueDays': 0,
        }
      ],
      'counters': {'current': 1, 'overdue': 0},
    });
    resaJson = jsonEncode({'hasCard': true, 'holds': []});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
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

  });

  // Le réseau est simulé par des fonctions : `testWidgets` tourne en horloge
  // SIMULÉE, où une entrée-sortie réseau réelle ne se termine jamais pendant
  // les `pump` — l'écran serait intestable, et c'est justement celui qui doit
  // survivre à une panne.
  Future<Object> chargerPrets() async {
    if (horsLigne) throw const SocketException('réseau coupé');
    return jsonDecode(pretsJson) as Object;
  }

  Future<Object> chargerResa() async {
    if (horsLigne) throw const SocketException('réseau coupé');
    return jsonDecode(resaJson) as Object;
  }

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ReaderSpaceScreen(
        fetchLoans: chargerPrets,
        fetchHolds: chargerResa,
        renew: (_) async => RenewResult(ok: true),
        cancel: (_) async {},
        cache: OfflineCache(),
        now: () => t,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche les prêts avec une échéance en langage courant', (tester) async {
    await monter(tester);
    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget);
    // Dû le 16 à 16 h, on est le 14 : deux jours.
    expect(find.text('À rendre dans 2 jours'), findsOneWidget);
    // Données fraîches : aucun bandeau.
    expect(find.textContaining('Synchronisé'), findsNothing);
  });

  testWidgets('HORS LIGNE : les prêts restent affichés, datés, jamais effacés',
      (tester) async {
    await monter(tester);
    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget);

    // Le réseau tombe, l'usager tire pour rafraîchir.
    horsLigne = true;
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget,
        reason: 'une panne réseau ne doit JAMAIS vider la liste des prêts');
    expect(find.textContaining('Pas de réseau'), findsOneWidget,
        reason: 'et elle doit être signalée, pas passée sous silence');
  });

  testWidgets('« aucun prêt » n’est PAS « pas de carte »', (tester) async {
    pretsJson = jsonEncode(
        {'hasCard': true, 'current': [], 'counters': {'current': 0, 'overdue': 0}});
    await monter(tester);
    expect(find.text('Aucun prêt en cours'), findsOneWidget);
    expect(find.textContaining('au comptoir'), findsOneWidget);
  });

  testWidgets('sans carte : on dit quoi faire, pas « aucun prêt »', (tester) async {
    pretsJson = jsonEncode(
        {'hasCard': false, 'current': [], 'counters': {'current': 0, 'overdue': 0}});
    await monter(tester);
    expect(find.text('Pas encore de carte de bibliothèque'), findsOneWidget);
    expect(find.text('Aucun prêt en cours'), findsNothing,
        reason: 'dire « aucun prêt » à qui ne peut pas emprunter est un mensonge');
  });

  testWidgets('jamais synchronisé et hors ligne : écran expliqué, pas blanc',
      (tester) async {
    horsLigne = true;
    await monter(tester);
    expect(find.textContaining('Rien à afficher'), findsOneWidget);
    expect(find.textContaining('hors connexion'), findsOneWidget);
  });

  testWidgets('un retard est mis en évidence', (tester) async {
    pretsJson = jsonEncode({
      'hasCard': true,
      'current': [
        {
          'checkoutId': 'c1', 'recordId': 'r1', 'title': 'Anatomie générale',
          'itemBarcode': 'B', 'dueDate': '2026-08-10T16:00:00.000Z',
          'renewals': 0, 'overdue': true, 'overdueDays': 4,
        }
      ],
      'counters': {'current': 1, 'overdue': 1},
    });
    await monter(tester);
    expect(find.text('En retard de 4 jours'), findsOneWidget);
    expect(find.textContaining('1 en retard'), findsOneWidget);
  });

  testWidgets('HISTORIQUE : les retours passés sont affichés, avec la date',
      (tester) async {
    // Entrée relevée sur GET /reader/loans après un retour réel.
    pretsJson = jsonEncode({
      'hasCard': true,
      'current': [],
      'counters': {'current': 0, 'overdue': 0},
      'history': {
        'entries': [
          {
            'checkoutId': 'cc253f12-c2e3-4738-a563-c32cc0795f76',
            'recordId': 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
            'title': 'Droit constitutionnel burkinabè',
            'itemBarcode': 'BIB-000123',
            'checkoutDate': '2026-08-09T23:38:26.530Z',
            'dueDate': '2026-08-16T16:00:00.000Z',
            'returnDate': '2026-08-10T13:29:55.751Z',
          }
        ],
        'total': 1,
        'page': 1,
        'totalPages': 1,
      },
    });
    await monter(tester);
    expect(find.text('Historique'), findsOneWidget);
    expect(find.textContaining('Rendu le 10/08/2026'), findsOneWidget);
    // Rendu AVANT l'échéance : pas de mention de retard.
    expect(find.textContaining('en retard'), findsNothing);
  });

  testWidgets('un retour APRÈS l’échéance est signalé', (tester) async {
    pretsJson = jsonEncode({
      'hasCard': true, 'current': [], 'counters': {'current': 0, 'overdue': 0},
      'history': {
        'entries': [
          {
            'checkoutId': 'c9', 'recordId': 'r', 'title': 'Anatomie générale',
            'itemBarcode': 'B',
            'checkoutDate': '2026-07-20T09:00:00.000Z',
            'dueDate': '2026-08-01T16:00:00.000Z',
            'returnDate': '2026-08-05T10:00:00.000Z',
          }
        ],
        'total': 1, 'page': 1, 'totalPages': 1,
      },
    });
    await monter(tester);
    expect(find.textContaining('rendu en retard'), findsOneWidget);
  });

  testWidgets('historique tronqué : on DIT combien manquent', (tester) async {
    // On ne met en cache que la première page. Laisser croire que c'est tout
    // ferait conclure à un historique amputé.
    pretsJson = jsonEncode({
      'hasCard': true, 'current': [], 'counters': {'current': 0, 'overdue': 0},
      'history': {
        'entries': [
          {
            'checkoutId': 'c9', 'recordId': 'r', 'title': 'Anatomie générale',
            'itemBarcode': 'B',
            'checkoutDate': '2026-07-20T09:00:00.000Z',
            'dueDate': '2026-08-01T16:00:00.000Z',
            'returnDate': '2026-07-30T10:00:00.000Z',
          }
        ],
        'total': 42, 'page': 1, 'totalPages': 3,
      },
    });
    await monter(tester);
    expect(find.textContaining('sur 42'), findsOneWidget);
  });

  testWidgets('aucun historique : aucune section vide', (tester) async {
    await monter(tester);
    expect(find.text('Historique'), findsNothing);
  });

  testWidgets('une réservation prête prime sur son rang', (tester) async {
    resaJson = jsonEncode({
      'hasCard': true,
      'holds': [
        {'holdId': 'h1', 'recordId': 'r1', 'title': 'Précis de médecine',
         'status': 'AVAILABLE', 'position': 0}
      ],
    });
    await monter(tester);
    expect(find.text('Disponible — à retirer'), findsOneWidget);
  });
}
