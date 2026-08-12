import 'package:flutter/foundation.dart';

import '../models/reader_space.dart';

/// Rappels d'échéance — notifications LOCALES planifiées.
///
/// Pas de push, donc pas de Firebase : ce serait une dépendance Google de plus
/// dans un produit qui se revendique souverain, et le résultat pour l'étudiant
/// est identique. L'appareil connaît déjà les dates d'échéance ; il n'a besoin
/// de personne pour compter les jours.
///
/// Conséquence assumée : un prêt renouvelé pendant que l'appareil est hors
/// réseau garde son ancien rappel jusqu'à la prochaine synchronisation. Un
/// rappel en trop est bénin ; un rappel manquant ne l'est pas.

/// Un rappel à planifier.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });

  /// Identifiant STABLE, dérivé du prêt et du décalage. Deux planifications
  /// successives réécrivent donc le même rappel au lieu d'en empiler deux — un
  /// étudiant qui ouvre l'application cinq fois par jour ne doit pas recevoir
  /// cinq notifications identiques.
  final int id;

  final DateTime when;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.when == when &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, when, title, body);
}

/// Heure d'envoi des rappels, dans la journée.
///
/// 9 h : assez tôt pour qu'on puisse encore passer à la bibliothèque le jour
/// même, assez tard pour ne réveiller personne. Une notification à 2 h du
/// matin serait balayée sans être lue.
const int kHeureRappel = 9;

/// Décalages retenus : trois jours avant, et le jour même.
const List<int> kJoursAvant = [3, 0];

/// Identifiant stable d'un rappel — dérivé de l'identifiant du prêt.
///
/// `hashCode` d'une chaîne n'est pas stable entre exécutions de la VM sur
/// toutes les plateformes ; on calcule donc nous-mêmes, de façon déterministe.
/// Un identifiant instable ferait s'accumuler des rappels fantômes qu'on ne
/// saurait plus annuler.
int reminderId(String checkoutId, int joursAvant) {
  var h = 0;
  for (final c in checkoutId.codeUnits) {
    h = (h * 31 + c) & 0x3FFFFFF; // borné : Android exige un int 32 bits
  }
  return h * 10 + joursAvant;
}

/// Calcule les rappels à planifier pour une liste de prêts.
///
/// Règles, toutes destinées à ne jamais notifier pour rien :
///   · un prêt DÉJÀ en retard n'engendre aucun rappel — l'information est
///     visible en rouge dans « Mon espace », et une notification « à rendre
///     dans 3 jours » pour un livre en retard depuis une semaine serait fausse ;
///   · un rappel dont l'heure est PASSÉE n'est pas planifié : le système le
///     déclencherait immédiatement, et l'étudiant recevrait une alerte
///     « à rendre dans 3 jours » à l'instant où il ouvre l'application ;
///   · les dates sont calculées en heure LOCALE de l'appareil, à partir du jour
///     calendaire de l'échéance — la même règle d'affichage que les prêts.
List<Reminder> remindersFor(
  List<Loan> loans, {
  required DateTime now,
  List<int> joursAvant = kJoursAvant,
  int heure = kHeureRappel,
}) {
  final out = <Reminder>[];
  for (final l in loans) {
    if (l.overdue) continue;
    final due = l.dueDate.toLocal();
    for (final j in joursAvant) {
      final quand = DateTime(due.year, due.month, due.day - j, heure);
      if (!quand.isAfter(now)) continue;
      out.add(Reminder(
        id: reminderId(l.checkoutId, j),
        when: quand,
        title: j == 0 ? 'À rendre aujourd’hui' : 'À rendre dans $j jours',
        body: l.title,
      ));
    }
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}
