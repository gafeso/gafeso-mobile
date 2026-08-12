import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/models/reader_space.dart';

/// Modèles de l'espace lecteur.
///
/// Les charges utiles ci-dessous sont celles RELEVÉES SUR L'API en
/// fonctionnement (GET /reader/loans et /reader/holds, avec un vrai prêt et une
/// vraie réservation), copiées telles quelles. Si le backend renomme une clé,
/// ces tests échouent — c'est le seul moment utile pour l'apprendre.
void main() {
  // Relevé réel : awa@exemple.bf, un prêt en cours sur « Droit constitutionnel
  // burkinabè ». Noter dueDate à 16:00 — la règle d'échéance à heure fixe.
  const pretsReel = '''
{
  "hasCard": true,
  "current": [
    {
      "checkoutId": "cc253f12-c2e3-4738-a563-c32cc0795f76",
      "recordId": "bdefba53-70ee-4214-b83f-a4cc7f6bde75",
      "title": "Droit constitutionnel burkinabè",
      "itemBarcode": "BIB-000123",
      "dueDate": "2026-08-16T16:00:00.000Z",
      "renewals": 0,
      "overdue": false,
      "overdueDays": 0
    }
  ],
  "history": { "entries": [], "total": 0, "page": 1, "totalPages": 1 },
  "counters": { "current": 1, "overdue": 0 }
}''';

  const reservationsReel = '''
{
  "hasCard": true,
  "holds": [
    {
      "holdId": "07f68a00-f811-4a33-b715-3a9432b6a867",
      "recordId": "bdefba53-70ee-4214-b83f-a4cc7f6bde75",
      "title": "Droit constitutionnel burkinabè",
      "status": "AVAILABLE",
      "position": 0,
      "expiryDate": "2026-08-16T23:38:37.955Z"
    }
  ]
}''';

  group('ReaderLoans — charge utile réelle', () {
    test('décode le prêt tel que l’API le renvoie', () {
      final r = ReaderLoans.fromJson(jsonDecode(pretsReel) as Object);
      expect(r.hasCard, isTrue);
      expect(r.currentCount, 1);
      expect(r.overdueCount, 0);
      final p = r.current.single;
      expect(p.title, 'Droit constitutionnel burkinabè');
      expect(p.itemBarcode, 'BIB-000123');
      expect(p.dueDate.toUtc(), DateTime.utc(2026, 8, 16, 16, 0));
    });

    test('aller-retour JSON : ce qu’on met en cache se relit identique', () {
      // Le cache stocke `toJson()` ; s'il perd une clé, l'écran hors ligne
      // afficherait des prêts amputés sans que rien ne le signale.
      final a = ReaderLoans.fromJson(jsonDecode(pretsReel) as Object);
      final b = ReaderLoans.fromJson(jsonDecode(jsonEncode(a.toJson())) as Object);
      expect(b.current.single.toJson(), a.current.single.toJson());
      expect(b.hasCard, a.hasCard);
      expect(b.currentCount, a.currentCount);
    });

    test('« sans carte » est distinct de « aucun prêt »', () {
      final sansCarte = ReaderLoans.fromJson(
          jsonDecode('{"hasCard":false,"current":[],"counters":{"current":0,"overdue":0}}')
              as Object);
      expect(sansCarte.hasCard, isFalse);
      expect(sansCarte.current, isEmpty);
      // Les deux états rendent une liste vide : seul `hasCard` les sépare. Un
      // écran qui les confond dit « aucun prêt » à quelqu'un qui ne PEUT pas
      // emprunter.
    });

    test('tolère des champs absents sans lever', () {
      final r = ReaderLoans.fromJson(jsonDecode('{"current":[]}') as Object);
      expect(r.hasCard, isFalse);
      expect(r.currentCount, 0);
    });
  });

  group('Loan — échéance en jours CALENDAIRES', () {
    final pret = Loan.fromJson(
        (jsonDecode(pretsReel) as Map<String, dynamic>)['current'][0] as Map<String, dynamic>);

    test('un prêt dû aujourd’hui à 16 h est « à rendre aujourd’hui » dès le matin', () {
      // Une division par 24 h donnerait « 0 jour » ou « dans 6 heures » : un
      // lecteur compte des jours au calendrier, pas des tranches horaires.
      final matin = DateTime(2026, 8, 16, 9, 0).toUtc().toLocal();
      expect(pret.daysLeftFrom(matin), 0);
      expect(pret.dueLabelFrom(matin), 'À rendre aujourd’hui');
    });

    test('libellés de proximité', () {
      expect(pret.dueLabelFrom(DateTime(2026, 8, 15, 23, 0)), 'À rendre demain');
      expect(pret.dueLabelFrom(DateTime(2026, 8, 13, 8, 0)), 'À rendre dans 3 jours');
    });

    test('le retard vient du SERVEUR, pas d’un calcul local', () {
      // Le serveur connaît l'heure d'échéance et le fuseau de l'établissement.
      // Recalculer le retard sur l'appareil ferait diverger l'affichage de
      // l'amende réellement due.
      final enRetard = Loan.fromJson({
        'checkoutId': 'x', 'recordId': 'y', 'title': 'T', 'itemBarcode': 'B',
        'dueDate': '2026-08-01T16:00:00.000Z', 'renewals': 1,
        'overdue': true, 'overdueDays': 3,
      });
      expect(enRetard.dueLabelFrom(DateTime(2026, 8, 4)), 'En retard de 3 jours');
      expect(
        Loan.fromJson({
          'checkoutId': 'x', 'recordId': 'y', 'title': 'T', 'itemBarcode': 'B',
          'dueDate': '2026-08-01T16:00:00.000Z', 'renewals': 0,
          'overdue': true, 'overdueDays': 1,
        }).dueLabelFrom(DateTime(2026, 8, 2)),
        'En retard d’un jour',
      );
    });
  });

  group('ReaderHolds — charge utile réelle', () {
    test('décode la réservation telle que l’API la renvoie', () {
      final r = ReaderHolds.fromJson(jsonDecode(reservationsReel) as Object);
      final h = r.holds.single;
      expect(h.status, 'AVAILABLE');
      expect(h.isReady, isTrue);
      expect(h.position, 0);
    });

    test('« disponible » prime sur le rang dans la file', () {
      final r = ReaderHolds.fromJson(jsonDecode(reservationsReel) as Object);
      // Afficher « 1er de la file » ferait manquer qu'il faut aller CHERCHER
      // le livre — et la réservation expire.
      expect(r.holds.single.positionLabel, 'Disponible — à retirer');
    });

    test('files d’attente', () {
      Hold h(int p) => Hold.fromJson(
          {'holdId': 'h', 'recordId': 'r', 'title': 'T', 'status': 'PENDING', 'position': p});
      expect(h(1).positionLabel, 'Vous êtes le prochain');
      expect(h(4).positionLabel, '4ᵉ dans la file');
    });

    test('aller-retour JSON pour le cache', () {
      final a = ReaderHolds.fromJson(jsonDecode(reservationsReel) as Object);
      final b = ReaderHolds.fromJson(jsonDecode(jsonEncode(a.toJson())) as Object);
      expect(b.holds.single.toJson(), a.holds.single.toJson());
    });
  });
}
