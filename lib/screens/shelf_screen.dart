import 'package:flutter/material.dart';

import '../cache/offline_cache.dart';
import 'reader_space_screen.dart';
import 'library_card_screen.dart';
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
    } catch (_) {
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
      _notice = e.statusCode == 403
          ? 'Vous n’avez pas (ou plus) accès à ce document.'
          : 'Téléchargement impossible (${e.statusCode}).';
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
        title: const Text('Mon étagère'),
        actions: [
          IconButton(
            tooltip: 'Ma carte de lecteur',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LibraryCardScreen.from(
                api: widget.state.api,
                cache: OfflineCache(),
              ),
            )),
            icon: const Icon(Icons.badge_outlined),
          ),
          IconButton(
            tooltip: 'Rechercher dans le catalogue',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchScreen.from(
                api: widget.state.api,
                openRecord: (ctx, hit) => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => RecordScreen.from(
                    api: widget.state.api,
                    recordId: hit.id,
                    titleHint: hit.title,
                  ),
                )),
              ),
            )),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Mon espace (prêts et réservations)',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReaderSpaceScreen.from(
                api: widget.state.api,
                cache: OfflineCache(),
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
                      ? const Center(child: Text('Aucun document disponible.'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            children: [
                              for (final id in ids)
                                _DocTile(
                                  title: titles[id] ?? id,
                                  downloaded: _local.containsKey(id),
                                  busy: _busy.contains(id),
                                  onDownload: () => _download(
                                    _remote.firstWhere(
                                      (d) => d.docId == id,
                                      orElse: () => ShelfDocument(
                                        docId: id, title: titles[id] ?? id, fileFormat: 'PDF'),
                                    ),
                                  ),
                                  onOpen: () => _open(id, titles[id] ?? id),
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
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.title,
    required this.downloaded,
    required this.busy,
    required this.onDownload,
    required this.onOpen,
    required this.onRemove,
  });

  final String title;
  final bool downloaded;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(downloaded ? Icons.offline_pin : Icons.picture_as_pdf_outlined),
      title: Text(title),
      subtitle: Text(downloaded ? 'Disponible hors ligne' : 'À télécharger'),
      trailing: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : downloaded
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Retirer de l’appareil',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onRemove,
                    ),
                    FilledButton(onPressed: onOpen, child: const Text('Lire')),
                  ],
                )
              : OutlinedButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Télécharger'),
                ),
      onTap: downloaded ? onOpen : onDownload,
    );
  }
}
