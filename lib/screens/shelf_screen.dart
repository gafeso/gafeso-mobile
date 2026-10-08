import 'package:flutter/material.dart';

import '../cache/offline_cache.dart';
import 'reader_space_screen.dart';
import 'library_card_screen.dart';
import 'a_propos_screen.dart';
import 'record_screen.dart';
import 'search_screen.dart';

import '../api/gafeso_api.dart';
import '../app_state.dart';
import '../session/library_store.dart';
import 'reader_screen.dart';

/// Écran 3 — **« Mon étagère »**. Liste les documents autorisés
/// (`GET /offline/my-documents`), permet de les télécharger (licence + blob) puis de les ouvrir
/// dans le lecteur natif. À l'ouverture de l'écran, un **re-check de statut** en lot purge ce
/// qui a été révoqué ou a expiré.
///
/// Hors-ligne : la liste distante échoue, mais les documents déjà téléchargés restent lisibles
/// (licence et blob sont locaux).
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  List<ShelfDocument> _remote = [];
  Map<String, LocalDocument> _local = {};
  final _busy = <String>{};
  bool _loading = true;
  bool _offlineMode = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // 1) Re-check de statut à la (re)connexion : purge locale de ce qui n'est plus actif.
    try {
      final statuses = await widget.state.offline.refreshAll();
      // Seuls `revoked` et `expired` entraînent une purge. `unknown` signifie
      // que le serveur ne CONNAÎT pas la licence — absence d'information, pas
      // retrait de droit : annoncer un retrait serait faux, et le document est
      // conservé (voir OfflineService.refreshAll).
      final retires = statuses.entries
          .where((e) => e.value != 'active' && e.value != 'unknown')
          .toList();
      final inconnues = statuses.entries.where((e) => e.value == 'unknown').length;
      if (retires.isNotEmpty) {
        _notice = retires.length == 1
            ? 'Un document n’est plus accessible : il a été retiré de l’appareil.'
            : '${retires.length} documents ne sont plus accessibles : retirés de l’appareil.';
      } else if (inconnues > 0) {
        _notice = inconnues == 1
            ? 'Le serveur n’a pas reconnu un de vos documents : il est conservé, nouvelle vérification à la prochaine connexion.'
            : '$inconnues documents non reconnus par le serveur : ils sont conservés, nouvelle vérification à la prochaine connexion.';
      }
      _offlineMode = false;
    } catch (_) {
      // Pas de réseau : on garde ce qui est local, sans purge (on ne purge JAMAIS sur un
      // simple échec réseau — seule une réponse serveur « revoked/expired » purge).
      _offlineMode = true;
    }

    // 2) Liste distante (facultative hors-ligne) + bibliothèque locale.
    try {
      _remote = await widget.state.offline.api.myDocuments();
    } on GafesoApiException catch (e) {
      // ⚠ UN REFUS DU SERVEUR N'EST PAS UNE ABSENCE DE RÉSEAU.
      //
      // Ce `catch` prenait tout et concluait « hors ligne ». À l'expiration du
      // jeton (un jour, sans renouvellement), l'étagère annonçait donc une
      // panne de réseau sur un réseau qui marche — en désignant la mauvaise
      // cause, elle envoyait chercher au mauvais endroit.
      //
      // Le 401 est déjà signalé par le client, qui ramène à la connexion ; ici
      // on se contente de ne pas le maquiller en incident réseau.
      _remote = [];
      if (e.statusCode != 401) _offlineMode = true;
    } catch (_) {
      // Là, c'est bien le réseau (socket, DNS, délai) : la mention est juste.
      _offlineMode = true;
      _remote = [];
    }
    _local = await widget.state.offline.library.readAll();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _download(ShelfDocument doc) async {
    setState(() => _busy.add(doc.docId));
    try {
      await widget.state.offline.download(docId: doc.docId, title: doc.title);
      _local = await widget.state.offline.library.readAll();
      _notice = null;
    } on GafesoApiException catch (e) {
      // ⚠ LE SERVEUR A DÉJÀ RÉDIGÉ LE REFUS — on le lit au lieu d'en écrire un.
      //
      // Le produit distingue des situations qui n'appellent pas la même
      // conduite : « Appareil inconnu ou révoqué. » (se ré-enrôler),
      // « Vous n'avez pas accès à ce document. » (demander le droit),
      // « Licence révoquée : téléchargement refusé. » (le bail a été retiré),
      // « Document pas encore préparé pour la lecture hors-ligne. » (attendre,
      // et ce dernier est le cas le PLUS FRÉQUENT du fonds).
      //
      // L'écran les aplatissait : un 403 devenait une phrase unique, et tout le
      // reste un numéro nu — « Téléchargement impossible (400). » — alors que
      // ce 400 portait la seule explication utilisable par le lecteur.
      //
      // La chute ne sert que si le serveur n'a rien rédigé, et elle ne prétend
      // alors connaître aucun motif.
      _notice = e.motif(
        defaut: e.statusCode >= 500
            ? 'La bibliothèque est momentanément indisponible. Réessayez plus tard.'
            : 'Téléchargement refusé (${e.statusCode}).',
      );
    } catch (e) {
      _notice = 'Téléchargement impossible : $e';
    } finally {
      if (mounted) setState(() => _busy.remove(doc.docId));
    }
  }

  Future<void> _open(String docId, String title) async {
    final session = widget.state.session!;
    final params = await widget.state.offline.openParams(
      docId: docId,
      watermark: session.watermark(DateTime.now()),
    );
    if (!mounted) return;
    if (params == null) {
      setState(() => _notice = 'Ce document n’est plus disponible sur l’appareil.');
      _local = await widget.state.offline.library.readAll();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(title: title, params: params)),
    );
  }

  /// RENOUVELLEMENT d'un bail expiré.
  ///
  /// ⚠ C'est `download()` : il réémet une licence et RÉUTILISE le blob déjà sur
  /// l'appareil. Un étudiant en 3G ne repaie donc pas les mégaoctets pour une
  /// date — seule la licence est refaite.
  ///
  /// Un refus passe par `motif()` : la cause vient du serveur (droit perdu,
  /// embargo, appareil révoqué, document non préparé) et arrive intacte.
  Future<void> _renouveler(String docId, String titre) async {
    setState(() => _busy.add(docId));
    try {
      await widget.state.offline.download(docId: docId, title: titre);
      _local = await widget.state.offline.library.readAll();
      _notice = 'Licence renouvelée : « $titre » est lisible hors connexion.';
    } on GafesoApiException catch (e) {
      _notice = e.motif(
        defaut: e.statusCode >= 500
            ? 'La bibliothèque est momentanément indisponible. Réessayez plus tard.'
            : 'Renouvellement refusé (${e.statusCode}).',
      );
    } catch (e) {
      _notice = 'Renouvellement impossible : $e';
    } finally {
      if (mounted) setState(() => _busy.remove(docId));
    }
  }

  Future<void> _remove(String docId) async {
    await widget.state.offline.purge(docId);
    _local = await widget.state.offline.library.readAll();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Union : documents autorisés (distant) + déjà téléchargés (local, utile hors-ligne).
    final ids = <String>{..._remote.map((d) => d.docId), ..._local.keys};
    final titles = <String, String>{
      for (final d in _remote) d.docId: d.title,
      for (final e in _local.entries) e.key: e.value.title,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.state.titreEtagere),
        actions: [
          IconButton(
            tooltip: 'À propos',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AProposScreen()),
            ),
            icon: const Icon(Icons.info_outline),
          ),
          // ⚠ CARTE DE LECTEUR ET « MES PRÊTS » N'EXISTENT QUE S'IL Y A UNE
          // CIRCULATION PHYSIQUE. Une université virtuelle n'a ni comptoir, ni
          // exemplaire, ni carte à présenter : les afficher promettrait un
          // service absent, et les routes `/reader/*` refuseraient derrière.
          //
          // L'état vient du serveur (`GET /modules`), qui ouvre cette lecture à
          // tout compte authentifié précisément pour que les clients filtrent
          // leur menu — « refuser sans cacher laisse une interface qui ment ».
          //
          // ⚠ Tant que l'état est inconnu, on montre TOUT : amputer un menu sur
          // une incertitude est pire qu'une entrée de trop, car l'usager ne sait
          // pas que quelque chose manque et ne peut pas le réclamer.
          if (widget.state.circulationActive)
          IconButton(
            tooltip: 'Ma carte de lecteur',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SiCirculation(
                state: widget.state,
                child: LibraryCardScreen.from(
                  api: widget.state.api,
                  cache: OfflineCache(),
                ),
              ),
            )),
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            tooltip: 'Rechercher dans le catalogue',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchScreen.from(
                api: widget.state.api,
                covers: widget.state.covers,
                origine: widget.state.origineServeur,
                openRecord: (ctx, hit) => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RecordScreen.from(
                    api: widget.state.api,
                    recordId: hit.id,
                    titleHint: hit.title,
                    covers: widget.state.covers,
                    origine: widget.state.origineServeur,
                    circulation: widget.state.circulationActive,
                  ),
                )),
              ),
            )),
            icon: const Icon(Icons.search),
          ),
          if (widget.state.circulationActive)
          IconButton(
            tooltip: 'Mon espace (prêts et réservations)',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SiCirculation(
                state: widget.state,
                child: ReaderSpaceScreen.from(
                  api: widget.state.api,
                  cache: OfflineCache(),
                ),
              ),
            )),
            icon: const Icon(Icons.assignment_outlined),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') await widget.state.logout();
              if (v == 'tenant') await widget.state.changeTenant();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
              PopupMenuItem(value: 'tenant', child: Text('Changer d’école')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_offlineMode)
                  MaterialBanner(
                    content: const Text('Hors ligne — seuls les documents téléchargés sont lisibles.'),
                    leading: const Icon(Icons.cloud_off),
                    actions: [TextButton(onPressed: _load, child: const Text('Réessayer'))],
                  ),
                if (_notice != null)
                  MaterialBanner(
                    content: Text(_notice!),
                    leading: const Icon(Icons.info_outline),
                    actions: [
                      TextButton(
                        onPressed: () => setState(() => _notice = null),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                Expanded(
                  child: ids.isEmpty
                      ? _etagereVide()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            children: [
                              for (final id in ids)
                                _DocTile(
                                  title: titles[id] ?? id,
                                  downloaded: _local.containsKey(id),
                                  expiree: _local[id]?.estExpiree(DateTime.now()) ?? false,
                                  finDeBail: _local[id]?.expiresAt,
                                  busy: _busy.contains(id),
                                  onDownload: () => _download(
                                    _remote.firstWhere(
                                      (d) => d.docId == id,
                                      orElse: () => ShelfDocument(
                                        docId: id, title: titles[id] ?? id, fileFormat: 'PDF'),
                                    ),
                                  ),
                                  onOpen: () => _open(id, titles[id] ?? id),
                                  onRenew: () => _renouveler(id, titles[id] ?? id),
                                  onRemove: () => _remove(id),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  /// Étagère vide — et POURQUOI elle l'est.
  ///
  /// ⚠ « Aucun document disponible. » se lisait « la bibliothèque n'a rien », là
  /// où la vérité est « rien n'est PRÉPARÉ pour le hors-ligne ». Sur la démo,
  /// 352 notices et 88 fichiers existent, et aucun n'est ingéré : le lecteur
  /// aurait conclu à un fonds vide. Ce n'est pas un mensonge, c'est une phrase
  /// qui laisse se former une conclusion fausse — la même famille que
  /// « hors ligne » pour une session morte.
  ///
  /// L'app ne sait pas combien de fichiers existe le catalogue (ce chiffre est
  /// sur `/opac/chiffres`, qu'elle n'appelle pas). Elle ne l'invente donc pas :
  /// elle nomme la CONDITION qui manque, et elle indique où regarder.
  Widget _etagereVide() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _offlineMode ? Icons.cloud_off_outlined : Icons.download_outlined,
                size: 44,
                color: Colors.black26,
              ),
              const SizedBox(height: 14),
              Text(
                _offlineMode
                    // Hors ligne, on ne SAIT pas ce que la bibliothèque propose :
                    // on décrit l'appareil, pas le fonds.
                    ? 'Aucun document sur cet appareil.'
                    : 'Aucun document n’est prêt pour la lecture hors connexion.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              Text(
                _offlineMode
                    ? 'Reconnectez-vous pour voir ce que la bibliothèque propose.'
                    : 'Le catalogue peut contenir des documents numériques que la '
                        'bibliothèque n’a pas encore préparés. Cherchez-y : la fiche '
                        'd’une notice vous dira ce qu’il en est.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      );
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.title,
    required this.downloaded,
    required this.busy,
    required this.onDownload,
    required this.onOpen,
    required this.onRemove,
    this.expiree = false,
    this.finDeBail,
    this.onRenew,
  });

  final String title;
  final bool downloaded;
  final bool busy;

  /// Le bail est-il échu ? ⚠ Un document expiré est TOUJOURS sur l'appareil —
  /// c'est sa licence qui ne vaut plus, pas son contenu. On ne le purge donc
  /// pas : seule une réponse du serveur (`revoked`/`expired`) le retire, jamais
  /// l'horloge locale, qu'un changement d'heure suffirait à fausser.
  final bool expiree;
  final DateTime? finDeBail;

  final VoidCallback onDownload;
  final VoidCallback onOpen;
  final VoidCallback onRemove;
  final VoidCallback? onRenew;

  static String _jour(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    // ⚠ TROIS ÉTATS, ET LE TROISIÈME MANQUAIT. L'étagère annonçait « Disponible
    // hors ligne » pour un bail échu : le lecteur natif refusait ensuite
    // d'ouvrir, et rien n'avait prévenu. La date était pourtant sur l'appareil,
    // dans le corps de licence.
    final sousTitre = !downloaded
        ? 'À télécharger'
        : expiree
            ? (finDeBail == null
                ? 'Licence expirée — à renouveler'
                : 'Licence expirée le ${_jour(finDeBail!)} — à renouveler')
            : 'Disponible hors ligne';

    final icone = !downloaded
        ? Icons.picture_as_pdf_outlined
        : expiree
            ? Icons.lock_clock_outlined
            : Icons.offline_pin;

    Widget actions() {
      if (busy) {
        return const SizedBox(
          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
      }
      if (!downloaded) {
        return OutlinedButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.download),
          label: const Text('Télécharger'),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Retirer de l’appareil',
            icon: const Icon(Icons.delete_outline),
            onPressed: onRemove,
          ),
          // ⚠ « Renouveler » REMPLACE « Lire » quand le bail est échu : proposer
          // « Lire » mènerait au refus du lecteur, c'est-à-dire à un geste dont
          // on connaît déjà l'échec.
          expiree
              ? FilledButton(
                  onPressed: onRenew,
                  child: const Text('Renouveler'),
                )
              : FilledButton(onPressed: onOpen, child: const Text('Lire')),
        ],
      );
    }

    return ListTile(
      leading: Icon(
        icone,
        color: expiree && downloaded ? Colors.amber.shade800 : null,
      ),
      title: Text(title),
      subtitle: Text(
        sousTitre,
        style: expiree && downloaded
            ? TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w500)
            : null,
      ),
      trailing: actions(),
      onTap: !downloaded
          ? onDownload
          : expiree
              ? onRenew
              : onOpen,
    );
  }
}

/// Referme l'écran qu'il enveloppe dès que la circulation se révèle inactive.
///
/// ⚠ LE REFUS ARRIVE DE LA REQUÊTE QUE CET ÉCRAN VIENT DE FAIRE. Retirer
/// l'entrée du menu ne suffit donc pas : l'écran est déjà ouvert, et resterait
/// affiché, vide, à promettre des prêts qui n'existent pas ici. On le retire,
/// sans message — il n'y a pas d'échec à annoncer, seulement un service qui
/// n'est pas rendu dans cet établissement.
class SiCirculation extends StatefulWidget {
  const SiCirculation({super.key, required this.state, required this.child});

  final AppState state;
  final Widget child;

  @override
  State<SiCirculation> createState() => _SiCirculationState();
}

class _SiCirculationState extends State<SiCirculation> {
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_verifier);
  }

  @override
  void dispose() {
    widget.state.removeListener(_verifier);
    super.dispose();
  }

  void _verifier() {
    if (widget.state.circulationActive) return;
    // Après la frame : on ne dépile pas pendant que l'arbre se reconstruit.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
