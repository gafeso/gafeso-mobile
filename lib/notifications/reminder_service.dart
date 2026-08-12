import 'due_reminders.dart';
import '../models/reader_space.dart';

/// Ce que le service attend de la plateforme. Passé en interface pour que la
/// logique soit éprouvable sans greffon ni appareil.
abstract class ReminderSink {
  /// Demande l'autorisation de notifier. Rend `false` si elle est refusée.
  Future<bool> ensurePermission();

  Future<void> cancelAll();

  Future<void> schedule(Reminder reminder);
}

/// Issue d'une synchronisation des rappels.
enum ReminderOutcome {
  /// Rappels replanifiés.
  scheduled,

  /// L'usager a refusé les notifications. RIEN N'EST CASSÉ : les échéances
  /// restent visibles dans « Mon espace », avec les jours restants. C'est un
  /// confort en moins, pas une fonction en panne.
  denied,

  /// La plateforme a échoué (greffon absent, API indisponible). Même
  /// conséquence : on n'insiste pas, et on ne remonte rien à l'écran.
  unavailable,
}

/// Planifie les rappels d'échéance à partir des prêts.
///
/// APPELÉ À CHAQUE SYNCHRONISATION des prêts, et pas seulement au premier
/// lancement : c'est le seul moment où l'appareil apprend qu'un prêt a été
/// renouvelé, rendu, ou ajouté. On annule tout puis on replanifie, plutôt que
/// de tenir un différentiel — un différentiel qui dérive laisse des rappels
/// fantômes pour des livres déjà rendus, et personne ne saurait d'où ils
/// viennent.
class DueReminderService {
  DueReminderService(this.sink);

  final ReminderSink sink;

  Future<ReminderOutcome> sync(List<Loan> loans, {DateTime? now}) async {
    final rappels = remindersFor(loans, now: now ?? DateTime.now());
    try {
      // On demande l'autorisation MÊME s'il n'y a rien à planifier ? Non :
      // solliciter une permission sans rien à en faire est le meilleur moyen
      // de se la faire refuser une fois pour toutes. On ne la demande qu'au
      // premier prêt réel.
      if (rappels.isEmpty) {
        await sink.cancelAll();
        return ReminderOutcome.scheduled;
      }
      if (!await sink.ensurePermission()) return ReminderOutcome.denied;
      await sink.cancelAll();
      for (final r in rappels) {
        await sink.schedule(r);
      }
      return ReminderOutcome.scheduled;
    } catch (_) {
      // Une notification est un CONFORT. Qu'elle échoue ne doit jamais
      // empêcher l'écran des prêts de s'afficher, ni remonter une erreur à un
      // usager qui n'a rien demandé.
      return ReminderOutcome.unavailable;
    }
  }
}
