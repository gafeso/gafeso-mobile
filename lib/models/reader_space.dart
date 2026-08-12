import 'package:flutter/foundation.dart';

/// Modèles de l'espace lecteur.
///
/// Les formes sont celles OBSERVÉES sur l'API en fonctionnement
/// (`GET /reader/loans`, `GET /reader/holds`), relevées avec un vrai prêt et
/// une vraie réservation — pas déduites d'une documentation. Les tests rejouent
/// ces charges utiles telles quelles : si le backend change une clé, ils
/// échouent, ce qui est le seul moment utile pour l'apprendre.

/// Un prêt en cours.
@immutable
class Loan {
  const Loan({
    required this.checkoutId,
    required this.recordId,
    required this.title,
    required this.itemBarcode,
    required this.dueDate,
    required this.renewals,
    required this.overdue,
    required this.overdueDays,
  });

  final String checkoutId;
  final String recordId;
  final String title;
  final String itemBarcode;
  final DateTime dueDate;
  final int renewals;
  final bool overdue;
  final int overdueDays;

  /// Jours restants avant l'échéance, en JOURS CALENDAIRES du fuseau local.
  ///
  /// On ne divise pas une durée par 24 h : l'échéance tombe à une heure fixe
  /// (16 h côté serveur), et un prêt dû « aujourd'hui à 16 h » consulté à 9 h
  /// doit afficher « aujourd'hui », pas « 0,3 jour ». C'est la même règle que
  /// le décompte des retards côté backend — un lecteur compte des jours au
  /// calendrier, pas des tranches de 24 heures.
  int daysLeftFrom(DateTime now) {
    final d = DateTime(dueDate.toLocal().year, dueDate.toLocal().month, dueDate.toLocal().day);
    final n = DateTime(now.year, now.month, now.day);
    return d.difference(n).inDays;
  }

  /// Libellé d'échéance destiné à l'écran.
  String dueLabelFrom(DateTime now) {
    if (overdue) {
      return overdueDays <= 1 ? 'En retard d’un jour' : 'En retard de $overdueDays jours';
    }
    final j = daysLeftFrom(now);
    if (j < 0) return 'Échéance dépassée';
    if (j == 0) return 'À rendre aujourd’hui';
    if (j == 1) return 'À rendre demain';
    return 'À rendre dans $j jours';
  }

  static Loan fromJson(Map<String, dynamic> j) => Loan(
        checkoutId: j['checkoutId'] as String,
        recordId: j['recordId'] as String,
        title: j['title'] as String? ?? 'Sans titre',
        itemBarcode: j['itemBarcode'] as String? ?? '',
        dueDate: DateTime.parse(j['dueDate'] as String),
        renewals: (j['renewals'] as num?)?.toInt() ?? 0,
        overdue: j['overdue'] as bool? ?? false,
        overdueDays: (j['overdueDays'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'checkoutId': checkoutId,
        'recordId': recordId,
        'title': title,
        'itemBarcode': itemBarcode,
        'dueDate': dueDate.toIso8601String(),
        'renewals': renewals,
        'overdue': overdue,
        'overdueDays': overdueDays,
      };
}

/// Un prêt RENDU — entrée d'historique.
@immutable
class PastLoan {
  const PastLoan({
    required this.checkoutId,
    required this.title,
    required this.checkoutDate,
    required this.returnDate,
    required this.dueDate,
  });

  final String checkoutId;
  final String title;
  final DateTime checkoutDate;
  final DateTime returnDate;
  final DateTime dueDate;

  /// Le retour a-t-il eu lieu après l'échéance ?
  ///
  /// Calculé sur les DATES CIVILES, pas sur les instants : rendu le jour dit à
  /// 16 h 30 alors que l'échéance tombait à 16 h, un lecteur ne considère pas
  /// avoir été en retard. Même règle d'affichage que les jours restants — et
  /// le montant d'une éventuelle amende reste calculé par le SERVEUR.
  bool get returnedLate {
    final r = returnDate.toLocal();
    final d = dueDate.toLocal();
    return DateTime(r.year, r.month, r.day).isAfter(DateTime(d.year, d.month, d.day));
  }

  static PastLoan fromJson(Map<String, dynamic> j) => PastLoan(
        checkoutId: j['checkoutId'] as String,
        title: j['title'] as String? ?? 'Sans titre',
        checkoutDate: DateTime.parse(j['checkoutDate'] as String),
        returnDate: DateTime.parse(j['returnDate'] as String),
        dueDate: DateTime.parse(j['dueDate'] as String),
      );

  Map<String, dynamic> toJson() => {
        'checkoutId': checkoutId,
        'title': title,
        'checkoutDate': checkoutDate.toIso8601String(),
        'returnDate': returnDate.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
      };
}

/// Réponse de `GET /reader/loans`.
@immutable
class ReaderLoans {
  const ReaderLoans({
    required this.hasCard,
    required this.current,
    required this.currentCount,
    required this.overdueCount,
    this.history = const [],
    this.historyTotal = 0,
  });

  /// `false` quand le compte n'a pas encore de carte de bibliothèque.
  ///
  /// C'est un ÉTAT À PART ENTIÈRE, distinct de « aucun prêt ». L'API le
  /// distingue déjà ; l'écran doit le distinguer aussi, sinon un étudiant sans
  /// carte lit « aucun prêt en cours » et en conclut que tout va bien, alors
  /// qu'il ne peut simplement rien emprunter.
  final bool hasCard;
  final List<Loan> current;
  final int currentCount;
  final int overdueCount;

  /// Première page de l'historique. On ne met en cache QUE cette page : un
  /// historique complet grossit sans fin dans le coffre d'un appareil, pour
  /// une information qu'on consulte rarement et jamais en urgence.
  final List<PastLoan> history;
  final int historyTotal;

  static ReaderLoans fromJson(Object json) {
    final j = json as Map<String, dynamic>;
    final counters = (j['counters'] as Map<String, dynamic>?) ?? const {};
    return ReaderLoans(
      hasCard: j['hasCard'] as bool? ?? false,
      current: ((j['current'] as List?) ?? const [])
          .map((e) => Loan.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentCount: (counters['current'] as num?)?.toInt() ?? 0,
      overdueCount: (counters['overdue'] as num?)?.toInt() ?? 0,
      history: (((j['history'] as Map<String, dynamic>?) ?? const {})['entries'] as List? ??
              const [])
          .map((e) => PastLoan.fromJson(e as Map<String, dynamic>))
          .toList(),
      historyTotal:
          ((j['history'] as Map<String, dynamic>?)?['total'] as num?)?.toInt() ?? 0,
    );
  }

  Object toJson() => {
        'hasCard': hasCard,
        'current': current.map((l) => l.toJson()).toList(),
        'counters': {'current': currentCount, 'overdue': overdueCount},
        'history': {
          'entries': history.map((h) => h.toJson()).toList(),
          'total': historyTotal,
        },
      };
}

/// Une réservation.
@immutable
class Hold {
  const Hold({
    required this.holdId,
    required this.recordId,
    required this.title,
    required this.status,
    required this.position,
    this.expiryDate,
  });

  final String holdId;
  final String recordId;
  final String title;
  final String status;

  /// Position dans la file. `0` = disponible / en tête.
  final int position;
  final DateTime? expiryDate;

  bool get isReady => status == 'AVAILABLE';

  /// Libellé de position. `AVAILABLE` prime sur le rang : une réservation prête
  /// à retirer n'est plus une attente, et afficher « 1er de la file » ferait
  /// manquer le fait qu'il faut aller chercher le livre.
  String get positionLabel {
    if (isReady) return 'Disponible — à retirer';
    if (position <= 1) return 'Vous êtes le prochain';
    return '$positionᵉ dans la file';
  }

  static Hold fromJson(Map<String, dynamic> j) => Hold(
        holdId: j['holdId'] as String,
        recordId: j['recordId'] as String,
        title: j['title'] as String? ?? 'Sans titre',
        status: j['status'] as String? ?? 'PENDING',
        position: (j['position'] as num?)?.toInt() ?? 0,
        expiryDate: j['expiryDate'] == null
            ? null
            : DateTime.tryParse(j['expiryDate'] as String),
      );

  Map<String, dynamic> toJson() => {
        'holdId': holdId,
        'recordId': recordId,
        'title': title,
        'status': status,
        'position': position,
        'expiryDate': expiryDate?.toIso8601String(),
      };
}

/// Réponse de `GET /reader/holds`.
@immutable
class ReaderHolds {
  const ReaderHolds({required this.hasCard, required this.holds});

  final bool hasCard;
  final List<Hold> holds;

  static ReaderHolds fromJson(Object json) {
    final j = json as Map<String, dynamic>;
    return ReaderHolds(
      hasCard: j['hasCard'] as bool? ?? false,
      holds: ((j['holds'] as List?) ?? const [])
          .map((e) => Hold.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Object toJson() => {'hasCard': hasCard, 'holds': holds.map((h) => h.toJson()).toList()};
}
