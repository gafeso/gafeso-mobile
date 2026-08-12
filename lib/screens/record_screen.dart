import 'package:flutter/material.dart';

import '../api/gafeso_api.dart';
import '../models/catalog.dart';
import '../widgets/freshness_banner.dart';

/// Fiche notice — métadonnées, disponibilité des exemplaires, accès au
/// document numérique, réservation.
///
/// C'est le point de jonction du produit : on arrive ici par la recherche, et
/// on en repart soit vers le comptoir (exemplaire disponible), soit vers la
/// lecture hors ligne (document numérique), soit dans la file d'attente.
///
/// Comme la recherche, cet écran a besoin du réseau — il affiche un état de
/// notice que l'appareil n'a pas mémorisé. Il le DIT, avec la même règle :
/// jamais une exception, jamais un écran vide qui ressemblerait à « cette
/// notice n'existe pas ».
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.recordId,
    required this.titleHint,
    required this.fetchRecord,
    required this.placeHold,
    this.onOpenDigital,
  });

  final String recordId;

  /// Titre déjà connu par la liste de résultats. Affiché IMMÉDIATEMENT, avant
  /// même la réponse du serveur : l'usager doit voir qu'il a ouvert la bonne
  /// notice, pas une barre de progression anonyme.
  final String titleHint;

  final Future<Object> Function(String id) fetchRecord;
  final Future<RenewResult> Function(String recordId) placeHold;

  /// Ouverture du document numérique, quand il en existe un. Optionnel : la
  /// lecture hors ligne a son propre parcours (étagère), et on ne duplique pas
  /// ici la logique de licence.
  final void Function(BuildContext context, RecordDetail record)? onOpenDigital;

  static RecordScreen from({
    Key? key,
    required GafesoApi api,
    required String recordId,
    required String titleHint,
    void Function(BuildContext, RecordDetail)? onOpenDigital,
  }) =>
      RecordScreen(
        key: key,
        recordId: recordId,
        titleHint: titleHint,
        fetchRecord: api.catalogRecord,
        placeHold: api.placeHold,
        onOpenDigital: onOpenDigital,
      );

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  RecordDetail? _notice;
  bool _chargement = true;
  bool _reservation = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final n = RecordDetail.fromJson(await widget.fetchRecord(widget.recordId));
      if (!mounted) return;
      setState(() {
        _notice = n;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      final t = e.toString();
      setState(() {
        _chargement = false;
        _erreur = (t.contains('SocketException') ||
                t.contains('TimeoutException') ||
                t.contains('Connection'))
            ? 'reseau'
            : 'autre';
      });
    }
  }

  Future<void> _reserver() async {
    setState(() => _reservation = true);
    try {
      final r = await widget.placeHold(widget.recordId);
      if (!mounted) return;
      // Un refus est MOTIVÉ (déjà réservé, pas de carte, plafond) : le message
      // du serveur dit quoi faire, « échec » ne dirait rien.
      _dire(r.ok ? 'Réservation enregistrée.' : (r.reason ?? 'Réservation refusée.'));
      if (r.ok) await _charger();
    } catch (_) {
      if (mounted) _dire('Réservation impossible : pas de réseau.');
    } finally {
      if (mounted) setState(() => _reservation = false);
    }
  }

  void _dire(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final n = _notice;
    return Scaffold(
      // Le titre connu s'affiche tout de suite : voir qu'on a ouvert la bonne
      // notice vaut mieux qu'une barre de progression anonyme.
      appBar: AppBar(title: Text(n?.title ?? widget.titleHint)),
      body: _corps(n),
    );
  }

  Widget _corps(RecordDetail? n) {
    if (_erreur == 'reseau') {
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'Fiche indisponible hors connexion',
        message: 'Le détail d’une notice vient du serveur. '
            'Vos documents déjà téléchargés restent lisibles depuis l’étagère.',
        action: FilledButton(onPressed: _charger, child: const Text('Réessayer')),
      );
    }
    if (_erreur != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Fiche indisponible',
        message: 'La bibliothèque n’a pas pu répondre. Réessayez dans un instant.',
        action: FilledButton(onPressed: _charger, child: const Text('Réessayer')),
      );
    }
    if (_chargement || n == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(n.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        if (n.author != null) ...[
          const SizedBox(height: 4),
          Text(n.author!, style: const TextStyle(fontSize: 16, color: Colors.black87)),
        ],
        const SizedBox(height: 4),
        Text(
          [n.publisher, n.publishYear?.toString(), n.category]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(' · '),
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        if (n.summary != null && n.summary!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(n.summary!, style: const TextStyle(fontSize: 14)),
        ],

        if (n.hasDigitalCopy) ...[
          const SizedBox(height: 20),
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Document numérique disponible'),
              subtitle: const Text('Téléchargeable pour lecture hors connexion.'),
              onTap: widget.onOpenDigital == null
                  ? null
                  : () => widget.onOpenDigital!(context, n),
            ),
          ),
        ],

        const SizedBox(height: 20),
        Text('Exemplaires', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (n.items.isEmpty)
          const Text(
            'Aucun exemplaire physique pour cette notice.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          )
        else
          ...n.items.map((i) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  i.available ? Icons.check_circle_outline : Icons.remove_circle_outline,
                  color: i.available ? Colors.green.shade700 : Colors.orange.shade800,
                ),
                title: Text(i.statusLabel),
                subtitle: Text(
                  [i.location, i.callNumber].whereType<String>().join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
              )),

        const SizedBox(height: 20),
        if (n.availableCount > 0)
          // Disponible : on n'offre PAS de réserver. Envoyer attendre quelqu'un
          // qui peut emprunter tout de suite serait absurde.
          Card(
            color: Colors.green.shade50,
            child: const ListTile(
              leading: Icon(Icons.check_circle),
              title: Text('Disponible au comptoir'),
              subtitle: Text('Présentez votre carte de lecteur pour l’emprunter.'),
            ),
          )
        else if (n.canReserve)
          FilledButton.icon(
            onPressed: _reservation ? null : _reserver,
            icon: _reservation
                ? const SizedBox(
                    height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.bookmark_add_outlined),
            label: const Text('Réserver'),
          ),
      ],
    );
  }
}
