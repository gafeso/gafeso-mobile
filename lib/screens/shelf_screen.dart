import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/gafeso_theme.dart';

import '../cache/offline_cache.dart';
import 'reader_space_screen.dart';
import 'library_card_screen.dart';
import 'a_propos_screen.dart';
import 'qr_scan_screen.dart';
import 'record_screen.dart';
import 'search_screen.dart';

import '../api/gafeso_api.dart';
import '../api/scan.dart';
import '../app_state.dart';
import '../session/library_store.dart';
import '../models/catalog.dart';
import '../session/metadonnees_document.dart';
import '../session/preferences_affichage.dart';
import '../session/progress_store.dart';
import '../widgets/couverture_generee.dart';
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
  Map<String, Progression> _progression = {};
  bool _loading = true;
  bool _offlineMode = false;
  String? _notice;

  /// Filtres et tri de l'étagère — en mémoire d'écran, délibérément.
  /// Un filtre qui survit à la fermeture de l'app fait rouvrir une étagère
  /// amputée sans qu'on sache pourquoi ; celui-ci se remet à zéro tout seul.
  _EtatFiltre _filtreEtat = _EtatFiltre.tous;
  bool _surCetAppareil = false;
  _Tri _tri = _Tri.ajoutRecent;

  /// Grille ou liste. ⚠ MÉMORISÉ, contrairement aux filtres : un filtre qui
  /// survit rouvre une étagère amputée sans qu'on sache pourquoi, alors qu'une
  /// forme d'affichage qu'il faut rechoisir à chaque ouverture n'est pas un
  /// choix, c'est une corvée.
  final _affichage = PreferencesAffichage();
  bool _grille = true;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_lireAffichage());
    _ecouterLesLiens();
  }

  /// Liens `gafeso://notice?url=…` — à l'ouverture, et pendant que l'app vit.
  ///
  /// ⚠ L'ADRESSE REÇUE EST SOUMISE AU SERVEUR, exactement comme un QR scanné.
  /// N'importe quelle application peut émettre ce schéma : l'ouvrir sur parole
  /// reviendrait à laisser un tiers choisir ce que l'app affiche.
  void _ecouterLesLiens() {
    const canal = MethodChannel('com.gafeso/device');
    canal.setMethodCallHandler((call) async {
      if (call.method != 'lienRecu') return null;
      final url = (call.arguments as Map?)?['url'] as String?;
      if (url != null && url.isNotEmpty && mounted) await ouvrirAdresse(url);
      return null;
    });
    unawaited(() async {
      try {
        final url = await canal.invokeMethod<String>('lienInitial');
        if (url != null && url.isNotEmpty && mounted) await ouvrirAdresse(url);
      } catch (_) {
        // Canal absent (tests) : l'écran s'ouvre normalement.
      }
    }());
  }

  Future<void> _lireAffichage() async {
    final g = await _affichage.enGrille();
    if (mounted && g != _grille) setState(() => _grille = g);
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
    _progression = await widget.state.progression.readAll();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _download(ShelfDocument doc) async {
    setState(() => _busy.add(doc.docId));
    try {
      await widget.state.offline.download(
        docId: doc.docId,
        title: doc.title,
        // Servis par la route depuis rc8 : plus rien à aller chercher ailleurs.
        auteur: doc.auteur,
        domaine: doc.domaine,
        annee: doc.annee,
      );
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
    // ⚠ Reprise à la dernière page LUE SUR CET APPAREIL. La valeur vient du
    // coffre local ; elle n'a jamais été demandée au serveur et ne lui a jamais
    // été envoyée.
    final reprise = (await widget.state.progression.readAll())[docId];
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          title: title,
          params: params,
          docId: docId,
          progression: widget.state.progression,
          pageDepart: reprise?.page ?? 0,
        ),
      ),
    );
    // Au retour du lecteur, l'étagère doit montrer la nouvelle progression.
    if (!mounted) return;
    final maj = await widget.state.progression.readAll();
    if (mounted) setState(() => _progression = maj);
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

  void _ouvrirRecherche() => Navigator.of(context).push(MaterialPageRoute(
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
              // Ce que l'APPAREIL sait déjà : inutile de le redemander au
              // serveur, et cela marche hors ligne.
              estLocal: _local.containsKey(hit.id),
              progression: _progression[hit.id],
              // ⚠ LE BOUTON PRINCIPAL DE LA FICHE ÉTAIT INERTE. Faute de ce
              // rappel, `onOpenDigital` valait `null` et le bouton restait
              // désactivé : la fiche affichait « Télécharger », le lecteur
              // appuyait, rien ne se passait. C'était déjà vrai quand c'était
              // une carte à toucher — en faire un bouton n'a pas créé le
              // défaut, cela l'a rendu visible, et c'est exactement ce qu'on
              // attend d'un bouton.
              onOpenDigital: (ctx, n) => _depuisLaFiche(ctx, n),
            ),
          )),
        ),
      ));

  void _ouvrirCarte() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SiCirculation(
          state: widget.state,
          child: LibraryCardScreen.from(api: widget.state.api, cache: OfflineCache()),
        ),
      ));

  void _ouvrirEspace() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SiCirculation(
          state: widget.state,
          child: ReaderSpaceScreen.from(api: widget.state.api, cache: OfflineCache()),
        ),
      ));

  @override
  Widget build(BuildContext context) {
    // Union : documents autorisés (distant) + déjà téléchargés (local, utile hors-ligne).
    final tous = <String>{..._remote.map((d) => d.docId), ..._local.keys};
    final titles = <String, String>{
      for (final d in _remote) d.docId: d.title,
      for (final e in _local.entries) e.key: e.value.title,
    };
    final ids = _trier(_filtrer(tous, titles), titles);
    // ⚠ UNE SEULE lecture à reprendre, la plus récente. Proposer une rangée de
    // « continuer » transformerait un raccourci en liste de choix : on revient
    // dans une application de lecture pour reprendre là où on s'est arrêté, pas
    // pour arbitrer entre six reprises.
    final reprise = _lecturesEnCours().firstOrNull;

    return Scaffold(
      appBar: AppBar(
        // ⚠ RÉDUIRE PLUTÔT QUE ROGNER. Un titre tronqué en « Mon … » ne nomme
        // plus rien ; un titre légèrement plus petit se lit encore. `scaleDown`
        // n'agit QUE lorsque la place manque — à taille normale, rien ne bouge —
        // et il couvre du même geste les écrans étroits et les réglages
        // d'accessibilité qui grossissent le texte, qu'aucun choix de police
        // fixe ne peut anticiper.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(widget.state.titreEtagere),
        ),
        // ⚠ UNE ICÔNE ET UN MENU, PAS SIX. Sur un écran de 360 dp — la largeur de
        // référence Android, celle des téléphones d'entrée de gamme qui sont
        // l'essentiel du parc visé — six actions ne laissaient au titre qu'un
        // « Mon … » tronqué. Un écran dont on ne lit plus le nom ne se situe
        // plus : c'est la première information de la barre, et elle sautait.
        //
        // Reste en clair le seul geste qui part d'ici vers ailleurs à chaque
        // session : chercher. Tout le reste descend dans le menu, où ces
        // entrées gagnent d'ailleurs un libellé écrit plutôt qu'une icône à
        // deviner. « Actualiser » y descend aussi : l'écran se charge seul à
        // l'ouverture, et le bandeau hors-ligne porte déjà son « Réessayer ».
        actions: [
          IconButton(
            tooltip: _grille ? 'Afficher en liste' : 'Afficher en grille',
            onPressed: () {
              setState(() => _grille = !_grille);
              unawaited(_affichage.poser(grille: _grille));
            },
            // ⚠ L'ICÔNE MONTRE CE QU'ON OBTIENDRA, pas l'état courant : un
            // bouton qui affiche la forme déjà à l'écran se lit comme un
            // indicateur, et personne n'appuie dessus.
            icon: Icon(_grille ? Icons.view_list_outlined : Icons.grid_view_outlined),
          ),
          IconButton(
            tooltip: 'Rechercher dans le catalogue',
            onPressed: _ouvrirRecherche,
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            // ⚠ LE FILTRE ACTIF SE VOIT, MÊME MENU FERMÉ. Une étagère amputée
            // par un filtre est indiscernable d'une étagère vide, et c'est le
            // genre de doute qui fait conclure à une panne. L'icône change ;
            // elle ne prend pas de place en plus, ce qui compte — la barre a
            // DEUX emplacements, mesurés, et c'est ce budget qui garde le titre
            // entier sur 360 dp (voir test/barre_etagere_test.dart).
            icon: Icon(_filtreActif ? Icons.filter_alt : Icons.more_vert),
            onSelected: (v) async {
              switch (v) {
                case 'scanner':
                  await _scanner();
                case 'filtrer':
                  _ouvrirFiltres();
                case 'actualiser':
                  if (!_loading) _load();
                case 'carte':
                  _ouvrirCarte();
                case 'espace':
                  _ouvrirEspace();
                case 'apropos':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AProposScreen()),
                  );
                case 'logout':
                  await widget.state.logout();
                case 'tenant':
                  await widget.state.changeTenant();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'scanner', child: Text('Scanner une étiquette')),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'filtrer',
                child: Text(_filtreActif ? 'Filtrer et trier ·' : 'Filtrer et trier'),
              ),
              PopupMenuItem(
                value: 'actualiser',
                enabled: !_loading,
                child: const Text('Actualiser'),
              ),
              const PopupMenuDivider(),
              // ⚠ CARTE DE LECTEUR ET « MON ESPACE » N'EXISTENT QUE S'IL Y A UNE
              // CIRCULATION PHYSIQUE. Une université virtuelle n'a ni comptoir,
              // ni exemplaire, ni carte à présenter : les afficher promettrait
              // un service absent, et les routes `/reader/*` refuseraient
              // derrière.
              //
              // ⚠ Tant que l'état est inconnu, on montre TOUT : amputer un menu
              // sur une incertitude est pire qu'une entrée de trop, car l'usager
              // ne sait pas que quelque chose manque et ne peut pas le réclamer.
              if (widget.state.circulationActive) ...[
                const PopupMenuItem(value: 'carte', child: Text('Ma carte de lecteur')),
                const PopupMenuItem(value: 'espace', child: Text('Mes prêts et réservations')),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(value: 'apropos', child: Text('À propos')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Se déconnecter')),
              const PopupMenuItem(value: 'tenant', child: Text('Changer d’école')),
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
                  child: ids.isEmpty && reprise == null
                      ? _etagereVide()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(child: _compteurs()),
                              if (reprise != null)
                                SliverToBoxAdapter(
                                  child: _continuerLaLecture(reprise, titles),
                                ),
                              if (ids.isEmpty)
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Text(
                                      'Aucun document ne correspond à ce filtre.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: context.gafeso.texteSecondaire),
                                    ),
                                  ),
                                )
                              else if (_grille)
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                                  sliver: SliverGrid(
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 16,
                                      // Couverture au ratio 0,72, plus la place
                                      // du titre (2 lignes) et de l'état.
                                      childAspectRatio: 0.72 / 1.42,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (_, i) => _tuile(ids[i], titles),
                                      childCount: ids.length,
                                    ),
                                  ),
                                )
                              else
                                SliverList.builder(
                                  itemCount: ids.length,
                                  itemBuilder: (_, i) => _ligne(ids[i], titles),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  // ── Filtres, tri, compteurs ───────────────────────────────────────────────

  /// Emporter puis lire, depuis la FICHE.
  ///
  /// Le même geste qu'à l'étagère, déclenché d'ailleurs : si le document n'est
  /// pas encore sur l'appareil on le télécharge, puis on ouvre le lecteur. Les
  /// métadonnées viennent de la notice qu'on a sous les yeux — on ne retourne
  /// pas les redemander à l'étagère.
  Future<void> _depuisLaFiche(BuildContext ctx, RecordDetail n) async {
    if (!_local.containsKey(n.id)) {
      await _download(ShelfDocument(
        docId: n.id,
        title: n.title,
        fileFormat: n.digitalFormat ?? 'PDF',
        auteur: n.author,
        domaine: n.category,
        annee: n.publishYear,
      ));
      if (!_local.containsKey(n.id)) return; // le téléchargement a échoué, et il l'a dit
    }
    if (!mounted) return;
    await _open(n.id, n.title);
  }

  // ── Scanner un QR d'étiquette ─────────────────────────────────────────────

  /// ⚠ LA PERMISSION CAMÉRA SE DEMANDE AU GESTE, ET ON DIT POURQUOI AVANT.
  ///
  /// Android affiche sa propre boîte, qui ne dit rien de l'usage : « Autoriser
  /// Gafeso à prendre des photos ? ». Posée sans contexte, elle se refuse — et
  /// un refus se rattrape mal, l'usager devant ensuite aller la rétablir dans
  /// les réglages du système. On explique donc d'abord, en une phrase, puis on
  /// la demande.
  Future<void> _scanner() async {
    final continuer = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: context.couleurs.primary),
                  const SizedBox(width: 10),
                  const Text(
                    'Scanner l’étiquette d’un livre',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'La caméra sert UNIQUEMENT à lire le QR collé dans le livre, '
                'pour ouvrir sa fiche. Aucune photo n’est prise, conservée ni '
                'envoyée.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.gafeso.texteSecondaire,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Activer la caméra'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (continuer != true || !mounted) return;

    final charge = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => QrScanScreen(
        titre: 'Scanner l’étiquette',
        // Une adresse, et rien d'autre : le reste est ignoré en silence,
        // l'usager continue de viser.
        accepte: (c) => Uri.tryParse(c.trim())?.hasScheme ?? false,
      ),
    ));
    if (charge == null || !mounted) return;
    await ouvrirAdresse(charge);
  }

  /// Résout une adresse — scannée, ou reçue par un lien `gafeso://notice`.
  Future<void> ouvrirAdresse(String adresse) async {
    final r = await reconnaitreAdresse(
      widget.state.api,
      adresse,
      dejaSurLAppareil: _local.containsKey,
    );
    if (!mounted) return;
    switch (r) {
      case ScanNotice(notice: final n):
        final notice = RecordDetail.fromJson((n as Map).cast<String, dynamic>());
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecordScreen.from(
            api: widget.state.api,
            recordId: notice.id,
            titleHint: notice.title,
            covers: widget.state.covers,
            origine: widget.state.origineServeur,
            circulation: widget.state.circulationActive,
            estLocal: _local.containsKey(notice.id),
            progression: _progression[notice.id],
            onOpenDigital: (ctx, d) => _depuisLaFiche(ctx, d),
          ),
        ));
      case ScanDejaLa(docId: final id):
        // ⚠ Hors ligne devant un rayonnage : le document est là, on l'ouvre.
        await _open(id, titresConnus()[id] ?? id);
      case ScanAutreEtablissement(message: final m, adresse: final a):
        await _autreEtablissement(m, a);
      case ScanInconnue(message: final m):
        setState(() => _notice = m);
      case ScanHorsLigne():
        setState(() => _notice =
            'Pas de réseau : ce document n’est pas sur cet appareil, il faudra '
            'une connexion pour l’ouvrir.');
    }
  }

  Map<String, String> titresConnus() => {
        for (final d in _remote) d.docId: d.title,
        for (final e in _local.entries) e.key: e.value.title,
      };

  /// Le livre existe — ailleurs.
  Future<void> _autreEtablissement(String message, String adresse) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Une autre bibliothèque',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              // ⚠ LA PHRASE EST CELLE DU SERVEUR. Lui seul sait quels domaines
              // sont les siens, et il a déjà nommé l'établissement — la
              // réécrire ici ferait dire à l'application quelque chose qu'elle
              // ne sait pas.
              Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: context.gafeso.texteSecondaire,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Fermer'),
                  ),
                  const SizedBox(width: 8),
                  // ⚠ C'est l'ADRESSE SCANNÉE qu'on ouvre, pas un hôte
                  // redécoupé du message : lire une adresse dans une phrase
                  // destinée à un humain, c'est se lier à sa formulation.
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      unawaited(_ouvrirDansLeNavigateur(adresse));
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Ouvrir dans le navigateur'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ouvrirDansLeNavigateur(String adresse) async {
    try {
      await const MethodChannel('com.gafeso/device')
          .invokeMethod('ouvrirLien', {'url': adresse});
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Impossible d’ouvrir le navigateur. '
            'L’adresse est : $adresse');
      }
    }
  }

  /// Voir `metadonneesDocument` : la route d'abord, l'appareil ensuite, et
  /// champ par champ. La règle vit hors de cet écran parce qu'elle s'éprouve
  /// sans en monter un, et parce qu'elle sert à deux endroits.
  ({String? auteur, String? domaine, int? annee}) _meta(String id) =>
      metadonneesDocument(
        distant: _remote.where((d) => d.docId == id).firstOrNull,
        local: _local[id],
      );

  /// Un filtre est-il posé ? Sert à le SIGNALER, pas à le décorer.
  bool get _filtreActif =>
      _filtreEtat != _EtatFiltre.tous || _surCetAppareil || _tri != _Tri.ajoutRecent;

  /// Dans quel état de lecture est ce document ?
  ///
  /// ⚠ « Non commencé » n'est PAS « jamais ouvert par personne » : c'est
  /// « aucune progression sur CET appareil ». L'app ne sait rien des autres
  /// appareils, et ne doit pas laisser croire le contraire.
  _EtatFiltre _etatDe(String id) {
    final p = _progression[id];
    if (p == null) return _EtatFiltre.nonCommence;
    return p.termine ? _EtatFiltre.termine : _EtatFiltre.enCours;
  }

  List<String> _filtrer(Set<String> ids, Map<String, String> titles) => ids.where((id) {
        if (_surCetAppareil && !_local.containsKey(id)) return false;
        if (_filtreEtat != _EtatFiltre.tous && _etatDe(id) != _filtreEtat) return false;
        return true;
      }).toList();

  List<String> _trier(List<String> ids, Map<String, String> titles) {
    final l = [...ids];
    switch (_tri) {
      case _Tri.titre:
        l.sort((a, b) => (titles[a] ?? '').toLowerCase().compareTo((titles[b] ?? '').toLowerCase()));
      case _Tri.auteur:
        // ⚠ Les documents SANS auteur connu vont à la fin, pas en tête : une
        // chaîne vide trie avant tout le reste et mettrait les inconnus devant.
        l.sort((a, b) {
          final x = _local[a]?.auteur, y = _local[b]?.auteur;
          if (x == null && y == null) return 0;
          if (x == null) return 1;
          if (y == null) return -1;
          return x.toLowerCase().compareTo(y.toLowerCase());
        });
      case _Tri.ajoutRecent:
        // L'ordre rendu par le serveur, les documents locaux d'abord : c'est
        // l'ordre « ce que j'ai sous la main », celui qu'on veut par défaut.
        l.sort((a, b) {
          final la = _local.containsKey(a) ? 0 : 1;
          final lb = _local.containsKey(b) ? 0 : 1;
          return la.compareTo(lb);
        });
    }
    return l;
  }

  /// Les lectures commencées et non finies, la plus récente d'abord.
  List<Progression> _lecturesEnCours() {
    final l = _progression.values
        .where((p) => p.enCours && _local.containsKey(p.docId))
        .toList()
      ..sort((a, b) => b.majAt.compareTo(a.majAt));
    return l;
  }

  /// Bloc de compteurs — trois nombres, et rien qu'on ne sache.
  ///
  /// ⚠ Pas de « temps de lecture », pas de « pages lues cette semaine » : ces
  /// données n'existent pas. On compte ce que l'appareil sait vraiment.
  /// Trois compteurs en CARTES.
  ///
  /// ⚠ Pas de « temps de lecture », pas de « pages lues cette semaine » : ces
  /// données n'existent pas. On compte ce que l'appareil sait vraiment.
  /// Le dernier est en orange : « sur l'appareil » est le seul des trois qui
  /// dise quelque chose du HORS-LIGNE, et c'est ce que ce produit existe pour
  /// rendre possible.
  Widget _compteurs() {
    final enCours = _progression.values.where((p) => p.enCours).length;
    final termines = _progression.values.where((p) => p.termine).length;
    final locaux = _local.length;

    Widget carte(String valeur, String libelle, {bool accent = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            decoration: BoxDecoration(
              color: context.gafeso.carteSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.couleurs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                Text(
                  valeur,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: accent ? GafesoMarque.orange : context.couleurs.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  libelle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: context.gafeso.texteSecondaire),
                ),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          carte('$enCours', 'en cours'),
          const SizedBox(width: 10),
          carte('$termines', 'terminés'),
          const SizedBox(width: 10),
          carte('$locaux', 'sur l’appareil', accent: true),
        ],
      ),
    );
  }

  /// ⭐ « CONTINUER LA LECTURE » — la seule chose qu'on vient souvent faire.
  ///
  /// ⚠ Elle est ABSENTE s'il n'y a rien à reprendre. Une carte « Continuer »
  /// vide, ou pointant le premier document venu, ferait perdre du temps à
  /// chaque ouverture pour ne rien proposer.
  Widget _continuerLaLecture(Progression p, Map<String, String> titles) {
    final m = _meta(p.docId);
    final titre = titles[p.docId] ?? _local[p.docId]?.title ?? '';
    final annexe = [
      if (m.auteur != null) m.auteur!,
      if (m.annee != null) '${m.annee}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Material(
        color: context.gafeso.carteSurface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _open(p.docId, titre),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CouvertureGeneree(
                    titre: titre,
                    auteur: m.auteur,
                    type: _local[p.docId]?.type,
                    annee: m.annee,
                    domaine: m.domaine,
                    largeur: 92,
                    hauteur: 130,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUER LA LECTURE',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                          color: GafesoMarque.orange,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        titre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 17,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: context.gafeso.texteSurCarteSurface,
                        ),
                      ),
                      if (annexe.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          annexe,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.gafeso.texteSecondaire),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: p.part,
                          minHeight: 6,
                          backgroundColor: context.couleurs.outlineVariant.withValues(alpha: 0.4),
                          valueColor: const AlwaysStoppedAnimation(GafesoMarque.orange),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Page ${p.pageLisible} sur ${p.pages} · ${p.pourcent} %',
                        style: TextStyle(fontSize: 12, color: context.gafeso.texteSecondaire),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tuile de GRILLE : couverture au ratio 0,72, puis titre et état.
  Widget _tuile(String id, Map<String, String> titles) {
    final titre = titles[id] ?? id;
    final m = _meta(id);
    final local = _local[id];
    final sur = local != null;
    final expiree = local?.estExpiree(DateTime.now()) ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _ouvrirOuEmporter(id, titre),
      // ⚠ Le retrait est sous un APPUI LONG : la corbeille posée à côté du
      // titre se touchait par erreur, et elle occupait une place que la
      // couverture utilise mieux.
      onLongPress: sur ? () => _confirmerRetrait(id, titre) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 0.72,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LayoutBuilder(
                      builder: (_, c) => CouvertureGeneree(
                        titre: titre,
                        auteur: m.auteur,
                        type: local?.type,
                        annee: m.annee,
                        domaine: m.domaine,
                        largeur: c.maxWidth,
                        hauteur: c.maxHeight,
                      ),
                    ),
                  ),
                ),
                if (sur)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: expiree ? context.gafeso.avertissement : GafesoMarque.orangeFonce,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        expiree ? Icons.schedule : Icons.check,
                        size: 14,
                        color: context.gafeso.surAplatDeMarque,
                      ),
                    ),
                  ),
                if (_busy.contains(id))
                  Positioned.fill(
                    child: ColoredBox(
                      color: context.gafeso.voile,
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            titre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.25, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            sur ? _etatLisible(id) : 'À télécharger',
            style: TextStyle(fontSize: 11, color: context.gafeso.texteSecondaire),
          ),
        ],
      ),
    );
  }

  /// Ligne de LISTE : plus dense, même information.
  Widget _ligne(String id, Map<String, String> titles) {
    final titre = titles[id] ?? id;
    final m = _meta(id);
    final local = _local[id];
    final sur = local != null;
    final p = _progression[id];
    final annexe = [
      if (m.auteur != null) m.auteur!,
      if (m.annee != null) '${m.annee}',
    ].join(' · ');

    return InkWell(
      onTap: () => _ouvrirOuEmporter(id, titre),
      onLongPress: sur ? () => _confirmerRetrait(id, titre) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CouvertureGeneree(
                    titre: titre,
                    type: local?.type,
                    domaine: m.domaine,
                    largeur: 56,
                    hauteur: 78,
                  ),
                ),
                if (sur)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: GafesoMarque.orangeFonce,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check, size: 11, color: context.gafeso.surAplatDeMarque),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.25, fontWeight: FontWeight.w600),
                  ),
                  if (annexe.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      annexe,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.gafeso.texteSecondaire),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (p != null && p.enCours)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: p.part,
                        minHeight: 4,
                        backgroundColor: context.couleurs.outlineVariant.withValues(alpha: 0.4),
                        valueColor: const AlwaysStoppedAnimation(GafesoMarque.orange),
                      ),
                    )
                  else
                    Text(
                      sur ? _etatLisible(id) : 'À télécharger',
                      style: TextStyle(fontSize: 11, color: context.gafeso.texteSecondaire),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (_busy.contains(id))
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.chevron_right, color: context.gafeso.texteSecondaire),
          ],
        ),
      ),
    );
  }

  /// ⚠ TOUTE LA LIGNE — ET TOUTE LA TUILE — OUVRE LE DOCUMENT. Le bouton
  /// « Lire » posé à droite n'était atteignable qu'au pouce droit et ne disait
  /// rien de plus que la ligne elle-même. Si le document n'est pas encore là,
  /// le même geste l'emporte d'abord : c'est la même intention.
  Future<void> _ouvrirOuEmporter(String id, String titre) async {
    final local = _local[id];
    if (local == null) {
      await _download(_remote.firstWhere(
        (d) => d.docId == id,
        orElse: () => ShelfDocument(docId: id, title: titre, fileFormat: 'PDF'),
      ));
      return;
    }
    if (local.estExpiree(DateTime.now())) {
      await _renouveler(id, titre);
      return;
    }
    await _open(id, titre);
  }

  /// État de lecture, en toutes lettres sous la couverture.
  String _etatLisible(String id) {
    final p = _progression[id];
    if (p == null) return 'Non commencé';
    if (p.termine) return 'Terminé';
    return '${p.pourcent} %';
  }

  /// ⚠ LE RETRAIT PASSE PAR UN APPUI LONG ET UNE CONFIRMATION, et la phrase
  /// compte autant que le bouton : « retirer » peut se lire « je perds ce
  /// document ». On dit donc ce qui reste vrai — le droit de lecture n'est pas
  /// touché, le fichier se retéléchargera.
  Future<void> _confirmerRetrait(String id, String titre) async {
    final retirer = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Retirer « $titre » de cet appareil ?',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                'Le document reste dans votre bibliothèque : vous pourrez le '
                'télécharger de nouveau tant que votre droit de lecture est valide.',
                style: TextStyle(fontSize: 13, color: context.gafeso.texteSecondaire, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Annuler'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      // ⚠ EN FOND, avec du texte blanc (6,69:1). Posé comme
                      // texte sur une carte sombre, ce rouge tombe à 2,37:1 —
                      // un geste destructeur doit se lire dans les deux thèmes.
                      backgroundColor: context.gafeso.retrait,
                      foregroundColor: context.gafeso.surAplatDeMarque,
                    ),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Retirer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (retirer == true) await _remove(id);
  }

  /// Feuille du bas : état, « sur cet appareil », tri, réinitialiser.
  void _ouvrirFiltres() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, poser) {
          void maj(void Function() f) {
            poser(f);
            setState(f);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('État de lecture',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.gafeso.texteSecondaire)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in _EtatFiltre.values)
                        ChoiceChip(
                          label: Text(e.libelle),
                          selected: _filtreEtat == e,
                          onSelected: (_) => maj(() => _filtreEtat = e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sur cet appareil'),
                    subtitle: const Text('Seulement les documents déjà téléchargés'),
                    value: _surCetAppareil,
                    onChanged: (v) => maj(() => _surCetAppareil = v),
                  ),
                  const SizedBox(height: 8),
                  Text('Trier par',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.gafeso.texteSecondaire)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final t in _Tri.values)
                        ChoiceChip(
                          label: Text(t.libelle),
                          selected: _tri == t,
                          onSelected: (_) => maj(() => _tri = t),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => maj(() {
                        _filtreEtat = _EtatFiltre.tous;
                        _surCetAppareil = false;
                        _tri = _Tri.ajoutRecent;
                      }),
                      child: const Text('Réinitialiser'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
                color: context.couleurs.scrim.withValues(alpha: 0.35),
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
                style: TextStyle(fontSize: 13, color: context.gafeso.texteSecondaire, height: 1.4),
              ),
            ],
          ),
        ),
      );
}

/// État de lecture, tel que l'étagère le filtre.
///
/// ⚠ Trois états, pas quatre : il n'y a pas d'« abandonné ». L'app ne sait pas
/// si quelqu'un a renoncé ou s'il reprendra demain, et prétendre le deviner
/// mettrait une étiquette fausse sur la moitié d'une étagère.
enum _EtatFiltre {
  tous('Tous'),
  nonCommence('Non commencé'),
  enCours('En cours'),
  termine('Terminé');

  const _EtatFiltre(this.libelle);
  final String libelle;
}

/// Ordre d'affichage.
///
/// ⚠ Pas de « plus lu », pas de « mieux noté » : ces données n'existent pas.
enum _Tri {
  ajoutRecent('Ajout récent'),
  titre('Titre'),
  auteur('Auteur');

  const _Tri(this.libelle);
  final String libelle;
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
