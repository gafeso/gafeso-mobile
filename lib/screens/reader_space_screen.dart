import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/gafeso_theme.dart';

import '../api/gafeso_api.dart';
import '../cache/offline_cache.dart';
import '../models/reader_space.dart';
import '../notifications/local_reminder_sink.dart';
import '../notifications/reminder_service.dart';
import '../widgets/freshness_banner.dart';

/// Mon espace lecteur — prêts et réservations.
///
/// Premier consommateur du socle hors ligne : l'écran s'affiche depuis la
/// dernière synchronisation, le réseau ne fait que rafraîchir, et une panne
/// n'efface rien.
///
/// C'est l'information la plus consultée du produit, et celle qu'on regarde
/// justement là où le réseau manque — au comptoir, dans une salle de lecture.
class ReaderSpaceScreen extends StatefulWidget {
  const ReaderSpaceScreen({
    super.key,
    required this.fetchLoans,
    required this.fetchHolds,
    required this.renew,
    required this.cancel,
    required this.cache,
    this.now,
    this.reminders,
  });

  /// Planificateur de rappels d'échéance. Optionnel : absent en test, et son
  /// absence ne change rien à l'écran — une notification est un confort.
  final DueReminderService? reminders;

  /// Dépendances passées en FONCTIONS, pas en client concret.
  ///
  /// Ce n'est pas de la ceinture de test : `testWidgets` tourne en horloge
  /// SIMULÉE, où une entrée-sortie réseau réelle ne se termine jamais pendant
  /// les `pump`. Un écran couplé au client HTTP n'est donc pas testable du
  /// tout — et c'est précisément cet écran, celui qui doit survivre à une
  /// panne de réseau, qu'il faut pouvoir éprouver hors ligne.
  final Future<Object> Function() fetchLoans;
  final Future<Object> Function() fetchHolds;
  final Future<RenewResult> Function(String checkoutId) renew;
  final Future<void> Function(String holdId) cancel;

  /// Construit l'écran à partir du client réel.
  static ReaderSpaceScreen from({
    Key? key,
    required GafesoApi api,
    required OfflineCache cache,
    DateTime Function()? now,
  }) =>
      ReaderSpaceScreen(
        key: key,
        fetchLoans: api.readerLoans,
        fetchHolds: api.readerHolds,
        renew: api.renewLoan,
        cancel: api.cancelHold,
        cache: cache,
        now: now,
        reminders: DueReminderService(LocalReminderSink()),
      );

  final OfflineCache cache;

  /// Injectable pour les tests : sans cela les assertions dépendraient de
  /// l'heure de la machine et deviendraient instables une fois par jour.
  final DateTime Function()? now;

  @override
  State<ReaderSpaceScreen> createState() => _ReaderSpaceScreenState();
}

class _ReaderSpaceScreenState extends State<ReaderSpaceScreen> {
  Cached<ReaderLoans> _prets = const Cached<ReaderLoans>();
  Cached<ReaderHolds> _reservations = const Cached<ReaderHolds>();
  bool _chargement = true;
  String? _action;

  DateTime get _maintenant => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _rafraichir();
  }

  Future<void> _rafraichir() async {
    setState(() => _chargement = true);
    final p = await loadCached<ReaderLoans>(
      cache: widget.cache,
      resource: 'reader.loans',
      fromJson: ReaderLoans.fromJson,
      toJson: (v) => v.toJson(),
      fetch: () async => ReaderLoans.fromJson(await widget.fetchLoans()),
      clock: () => _maintenant,
    );
    final r = await loadCached<ReaderHolds>(
      cache: widget.cache,
      resource: 'reader.holds',
      fromJson: ReaderHolds.fromJson,
      toJson: (v) => v.toJson(),
      fetch: () async => ReaderHolds.fromJson(await widget.fetchHolds()),
      clock: () => _maintenant,
    );
    if (!mounted) return;
    setState(() {
      _prets = p;
      _reservations = r;
      _chargement = false;
    });

    // Rappels replanifiés à CHAQUE synchronisation : c'est le seul moment où
    // l'appareil apprend qu'un prêt a été renouvelé, rendu ou ajouté. Sur
    // données de cache aussi — elles restent les meilleures connues.
    final prets = p.value;
    if (prets != null && widget.reminders != null) {
      // Sans await : l'écran ne doit pas attendre une notification pour
      // s'afficher, et un échec de planification ne le concerne pas.
      unawaited(widget.reminders!.sync(prets.current, now: _maintenant));
    }
  }

  Future<void> _renouveler(Loan pret) async {
    setState(() => _action = pret.checkoutId);
    try {
      final res = await widget.renew(pret.checkoutId);
      if (!mounted) return;
      // Un refus est MOTIVÉ : on affiche la raison du serveur, qui dit à
      // l'usager s'il doit rendre, attendre, ou ne rien faire.
      _dire(res.ok ? 'Prêt renouvelé.' : (res.reason ?? 'Renouvellement refusé.'));
      if (res.ok) await _rafraichir();
    } catch (_) {
      if (mounted) _dire('Renouvellement impossible : pas de réseau.');
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  Future<void> _annuler(Hold h) async {
    setState(() => _action = h.holdId);
    try {
      await widget.cancel(h.holdId);
      if (!mounted) return;
      _dire('Réservation annulée.');
      await _rafraichir();
    } catch (_) {
      if (mounted) _dire('Annulation impossible : pas de réseau.');
    } finally {
      if (mounted) setState(() => _action = null);
    }
  }

  void _dire(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final prets = _prets.value;
    final resa = _reservations.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Mon espace')),
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        child: ListView(
          children: [
            // Le bandeau porte la synchro la PLUS ANCIENNE des deux ressources :
            // annoncer la plus récente laisserait croire que tout est à jour
            // alors qu'une moitié de l'écran ne l'est pas.
            FreshnessBanner(
              syncedAt: _plusAncienne(_prets.syncedAt, _reservations.syncedAt),
              lastError: _prets.lastError ?? _reservations.lastError,
              onRefresh: _chargement ? null : _rafraichir,
              now: _maintenant,
              maxAge: Volatility.emprunts,
            ),
            if (_chargement && !_prets.hasValue)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ..._sectionPrets(prets),
              ..._sectionReservations(resa),
              ..._sectionHistorique(prets),
            ],
          ],
        ),
      ),
    );
  }

  static DateTime? _plusAncienne(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a ?? b;
    return a.isBefore(b) ? a : b;
  }

  List<Widget> _sectionPrets(ReaderLoans? prets) {
    if (prets == null) {
      return const [
        EmptyState(
          icon: Icons.cloud_off,
          title: 'Rien à afficher pour l’instant',
          message: 'Connectez-vous une fois au réseau : vos prêts resteront '
              'ensuite consultables hors connexion.',
        ),
      ];
    }
    // « Sans carte » n'est PAS « aucun prêt ». Les confondre dirait « tout va
    // bien » à quelqu'un qui ne peut simplement rien emprunter.
    if (!prets.hasCard) {
      return const [
        EmptyState(
          icon: Icons.badge_outlined,
          title: 'Pas encore de carte de bibliothèque',
          message: 'Présentez-vous au comptoir pour activer votre carte. '
              'Vous pourrez ensuite emprunter et réserver.',
        ),
      ];
    }
    if (prets.current.isEmpty) {
      return const [
        EmptyState(
          title: 'Aucun prêt en cours',
          message: 'Empruntez un ouvrage au comptoir : il apparaîtra ici, '
              'avec sa date de retour.',
        ),
      ];
    }
    return [
      _titre('Mes prêts', '${prets.currentCount} en cours'
          '${prets.overdueCount > 0 ? ' · ${prets.overdueCount} en retard' : ''}'),
      ...prets.current.map(_cartePret),
    ];
  }

  Widget _cartePret(Loan p) {
    final enCours = _action == p.checkoutId;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(p.title),
        subtitle: Text(
          p.dueLabelFrom(_maintenant),
          style: TextStyle(
            color: p.overdue ? context.couleurs.error : null,
            fontWeight: p.overdue ? FontWeight.bold : null,
          ),
        ),
        trailing: enCours
            ? const SizedBox(
                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: _action != null ? null : () => _renouveler(p),
                child: const Text('Renouveler'),
              ),
      ),
    );
  }

  List<Widget> _sectionReservations(ReaderHolds? resa) {
    if (resa == null || resa.holds.isEmpty) return const [];
    return [
      _titre('Mes réservations', '${resa.holds.length}'),
      ...resa.holds.map((h) => Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              title: Text(h.title),
              subtitle: Text(
                h.positionLabel,
                style: TextStyle(
                  color: h.isReady ? context.gafeso.succes : null,
                  fontWeight: h.isReady ? FontWeight.bold : null,
                ),
              ),
              trailing: _action == h.holdId
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _action != null ? null : () => _annuler(h),
                      child: const Text('Annuler'),
                    ),
            ),
          )),
    ];
  }

  /// Historique — replié par défaut.
  ///
  /// C'est une information qu'on consulte rarement et jamais en urgence :
  /// dépliée, elle repousserait les prêts en cours, qui sont la raison d'être
  /// de l'écran, sous la ligne de flottaison.
  List<Widget> _sectionHistorique(ReaderLoans? prets) {
    if (prets == null || prets.history.isEmpty) return const [];
    return [
      _titre('Historique', '${prets.historyTotal} rendu'
          '${prets.historyTotal > 1 ? 's' : ''}'),
      ...prets.history.map((h) => ListTile(
            dense: true,
            title: Text(h.title),
            subtitle: Text(
              'Rendu le ${_jour(h.returnDate)}'
              '${h.returnedLate ? ' · rendu en retard' : ''}',
              style: TextStyle(color: h.returnedLate ? context.gafeso.avertissement : null),
            ),
          )),
      if (prets.historyTotal > prets.history.length)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Text(
            // On ne met en cache que la première page : dire combien
            // manquent vaut mieux que laisser croire que c'est tout.
            'Les ${prets.history.length} derniers retours sont affichés '
            'sur ${prets.historyTotal}.',
            style: TextStyle(fontSize: 12, color: context.gafeso.texteSecondaire),
          ),
        ),
    ];
  }

  static String _jour(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  Widget _titre(String t, String compte) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(compte, style: TextStyle(fontSize: 12, color: context.gafeso.texteSecondaire)),
          ],
        ),
      );
}
