import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/models/reader_space.dart';
import 'package:gafeso_mobile/notifications/due_reminders.dart';
import 'package:gafeso_mobile/notifications/reminder_service.dart';

class _Sink implements ReminderSink {
  _Sink({this.autorise = true, this.casse = false});

  final bool autorise;
  final bool casse;
  int demandes = 0;
  int annulations = 0;
  final List<Reminder> planifies = [];

  @override
  Future<bool> ensurePermission() async {
    demandes++;
    if (casse) throw Exception('greffon absent');
    return autorise;
  }

  @override
  Future<void> cancelAll() async {
    if (casse) throw Exception('greffon absent');
    annulations++;
  }

  @override
  Future<void> schedule(Reminder r) async {
    if (casse) throw Exception('greffon absent');
    planifies.add(r);
  }
}

void main() {
  Loan pret(String id, String dueIso) => Loan.fromJson({
        'checkoutId': id, 'recordId': 'r', 'title': 'Anatomie générale',
        'itemBarcode': 'B', 'dueDate': dueIso, 'renewals': 0,
        'overdue': false, 'overdueDays': 0,
      });

  final now = DateTime(2026, 8, 10, 8);

  test('planifie les rappels des prêts en cours', () async {
    final s = _Sink();
    final r = await DueReminderService(s).sync(
      [pret('c1', '2026-08-16T16:00:00.000Z')],
      now: now,
    );
    expect(r, ReminderOutcome.scheduled);
    expect(s.planifies.length, 2);
    expect(s.annulations, 1, reason: 'on annule avant de replanifier');
  });

  test('PERMISSION REFUSÉE : rien n’est cassé, rien n’est planifié', () async {
    // Les échéances restent visibles dans « Mon espace ». C'est un confort en
    // moins, pas une fonction en panne.
    final s = _Sink(autorise: false);
    final r = await DueReminderService(s).sync(
      [pret('c1', '2026-08-16T16:00:00.000Z')],
      now: now,
    );
    expect(r, ReminderOutcome.denied);
    expect(s.planifies, isEmpty);
  });

  test('la permission n’est PAS demandée quand il n’y a rien à planifier', () async {
    // Solliciter une autorisation sans rien à en faire est le meilleur moyen
    // de se la faire refuser une fois pour toutes.
    final s = _Sink();
    final r = await DueReminderService(s).sync(const [], now: now);
    expect(s.demandes, 0);
    expect(r, ReminderOutcome.scheduled);
    expect(s.annulations, 1, reason: 'les anciens rappels doivent disparaître');
  });

  test('plus aucun prêt : les rappels précédents sont ANNULÉS', () async {
    // Sinon l'étudiant reçoit « à rendre aujourd'hui » pour un livre rendu la
    // semaine dernière, et n'a aucun moyen de comprendre pourquoi.
    final s = _Sink();
    await DueReminderService(s).sync([pret('c1', '2026-08-16T16:00:00.000Z')], now: now);
    await DueReminderService(s).sync(const [], now: now);
    expect(s.annulations, 2);
  });

  test('PANNE de la plateforme : aucune exception ne remonte', () async {
    // Une notification est un confort ; qu'elle échoue ne doit jamais empêcher
    // l'écran des prêts de s'afficher.
    final s = _Sink(casse: true);
    final r = await DueReminderService(s).sync(
      [pret('c1', '2026-08-16T16:00:00.000Z')],
      now: now,
    );
    expect(r, ReminderOutcome.unavailable);
  });

  test('replanifier deux fois ne double pas les rappels', () async {
    final s = _Sink();
    final svc = DueReminderService(s);
    await svc.sync([pret('c1', '2026-08-16T16:00:00.000Z')], now: now);
    final premiers = s.planifies.map((r) => r.id).toList();
    s.planifies.clear();
    await svc.sync([pret('c1', '2026-08-16T16:00:00.000Z')], now: now);
    expect(s.planifies.map((r) => r.id).toList(), premiers,
        reason: 'mêmes identifiants : le système réécrit au lieu d’empiler');
  });
}
