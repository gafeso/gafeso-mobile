import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/models/reader_space.dart';
import 'package:gafeso_mobile/notifications/due_reminders.dart';

/// Rappels d'échéance — planification locale, sans Firebase.
void main() {
  Loan pret(String id, String dueIso, {bool overdue = false, int overdueDays = 0}) =>
      Loan.fromJson({
        'checkoutId': id,
        'recordId': 'r',
        'title': 'Droit constitutionnel burkinabè',
        'itemBarcode': 'B',
        'dueDate': dueIso,
        'renewals': 0,
        'overdue': overdue,
        'overdueDays': overdueDays,
      });

  test('deux rappels par prêt : J-3 et le jour même, à 9 h', () {
    final now = DateTime(2026, 8, 10, 8, 0);
    final r = remindersFor([pret('c1', '2026-08-16T16:00:00.000Z')], now: now);

    expect(r.length, 2);
    expect(r.first.when, DateTime(2026, 8, 13, 9));
    expect(r.first.title, 'À rendre dans 3 jours');
    expect(r.last.when, DateTime(2026, 8, 16, 9));
    expect(r.last.title, 'À rendre aujourd’hui');
    expect(r.first.body, contains('Droit constitutionnel'));
  });

  test('9 h : assez tôt pour passer à la bibliothèque, assez tard pour ne réveiller personne', () {
    final r = remindersFor([pret('c1', '2026-08-16T16:00:00.000Z')],
        now: DateTime(2026, 8, 10, 8));
    expect(r.every((x) => x.when.hour == 9), isTrue);
  });

  test('un rappel dont l’heure est PASSÉE n’est pas planifié', () {
    // Sinon le système le déclenche immédiatement : l'étudiant reçoit « à
    // rendre dans 3 jours » à l'instant où il ouvre l'application.
    final now = DateTime(2026, 8, 14, 10, 0); // J-3 (le 13 à 9 h) est passé
    final r = remindersFor([pret('c1', '2026-08-16T16:00:00.000Z')], now: now);

    expect(r.length, 1);
    expect(r.single.when, DateTime(2026, 8, 16, 9));
  });

  test('un prêt DÉJÀ en retard n’engendre aucun rappel', () {
    // « À rendre dans 3 jours » pour un livre en retard depuis une semaine
    // serait faux. Le retard est visible en rouge dans « Mon espace ».
    final r = remindersFor(
      [pret('c1', '2026-08-01T16:00:00.000Z', overdue: true, overdueDays: 9)],
      now: DateTime(2026, 8, 10),
    );
    expect(r, isEmpty);
  });

  test('échéance entièrement passée : rien, même sans drapeau de retard', () {
    final r = remindersFor([pret('c1', '2026-08-01T16:00:00.000Z')],
        now: DateTime(2026, 8, 10));
    expect(r, isEmpty);
  });

  group('identifiants', () {
    test('STABLES : replanifier réécrit le même rappel, n’en empile pas un second', () {
      // Un étudiant qui ouvre l'application cinq fois par jour ne doit pas
      // recevoir cinq notifications identiques.
      final a = remindersFor([pret('c1', '2026-08-16T16:00:00.000Z')],
          now: DateTime(2026, 8, 10, 8));
      final b = remindersFor([pret('c1', '2026-08-16T16:00:00.000Z')],
          now: DateTime(2026, 8, 10, 8));
      expect(a.map((r) => r.id).toList(), b.map((r) => r.id).toList());
    });

    test('DISTINCTS par prêt et par décalage', () {
      final r = remindersFor(
        [pret('c1', '2026-08-16T16:00:00.000Z'), pret('c2', '2026-08-18T16:00:00.000Z')],
        now: DateTime(2026, 8, 10, 8),
      );
      expect(r.map((x) => x.id).toSet().length, r.length);
    });

    test('bornés à un entier 32 bits — Android l’exige', () {
      final id = reminderId('cc253f12-c2e3-4738-a563-c32cc0795f76', 3);
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThan(1 << 31));
    });

    test('déterministes : pas le hashCode de chaîne, instable entre exécutions', () {
      expect(reminderId('abc', 0), reminderId('abc', 0));
      expect(reminderId('abc', 0), isNot(reminderId('abc', 3)));
      expect(reminderId('abc', 0), isNot(reminderId('abd', 0)));
    });
  });

  test('plusieurs prêts : rappels triés par date', () {
    final r = remindersFor(
      [pret('c1', '2026-08-20T16:00:00.000Z'), pret('c2', '2026-08-16T16:00:00.000Z')],
      now: DateTime(2026, 8, 10, 8),
    );
    for (var i = 1; i < r.length; i++) {
      expect(r[i].when.isBefore(r[i - 1].when), isFalse);
    }
  });

  test('aucun prêt : aucun rappel, pas d’exception', () {
    expect(remindersFor(const [], now: DateTime(2026, 8, 10)), isEmpty);
  });
}
