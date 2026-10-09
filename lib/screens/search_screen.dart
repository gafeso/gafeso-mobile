import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/gafeso_theme.dart';

import '../api/gafeso_api.dart';
import '../cache/cover_cache.dart';
import '../widgets/cover_image.dart';
import '../models/catalog.dart';
import '../widgets/freshness_banner.dart';

/// Recherche dans le catalogue.
///
/// LE SEUL ÉCRAN QUI EXIGE LE RÉSEAU, et il doit le DIRE plutôt qu'échouer.
///
/// Tous les autres écrans s'affichent depuis la dernière synchronisation ;
/// celui-ci ne le peut pas — on ne met pas un catalogue de dizaines de milliers
/// de notices dans le téléphone d'un étudiant. La conséquence tient en une
/// règle : quand le réseau manque, on l'annonce, on explique ce qui reste
/// possible hors connexion, et on offre de réessayer. Jamais une exception,
/// jamais une liste vide qui ressemblerait à « aucun résultat » — un lecteur
/// qui lit « aucun résultat » conclut que la bibliothèque n'a pas l'ouvrage.
///
/// FRUGALITÉ. Un étudiant en Afrique de l'Ouest paie ses données à l'octet :
///   · saisie temporisée (400 ms) — pas une requête par frappe ;
///   · pages de 20 résultats, chargées à la demande ;
///   · couvertures différées et petites, jamais préchargées.
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.search,
    required this.openRecord,
    this.covers,
    this.origine,
    this.explorer,
  });

  /// Cache des couvertures. Optionnel : sans lui, la liste affiche les
  /// substituts et ne tente aucun réseau — c'est ce que font les tests.
  final CoverCache? covers;
  final String? origine;

  /// Injectées en fonctions : `testWidgets` tourne en horloge simulée, où une
  /// E/S réseau réelle ne se termine jamais pendant les `pump`.
  final Future<Object> Function(String q, int page, String? recordType) search;
  final void Function(BuildContext context, SearchHit hit) openRecord;

  /// Exploration par domaine. `null` = pas d'exploration (tests, ou serveur qui
  /// ne la sert pas) : l'écran garde alors son invitation, il ne montre pas un
  /// bloc vide.
  final Future<Object> Function(String? category, int limit)? explorer;

  static SearchScreen from({
    Key? key,
    required GafesoApi api,
    required void Function(BuildContext, SearchHit) openRecord,
    CoverCache? covers,
    String? origine,
  }) =>
      SearchScreen(
        key: key,
        search: (q, page, type) => api.searchCatalog(q, page: page, recordType: type),
        explorer: (cat, limit) => api.searchCatalog('', limit: limit, category: cat),
        openRecord: openRecord,
        covers: covers,
        origine: origine,
      );

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _delaiSaisie = Duration(milliseconds: 400);

  final _controleur = TextEditingController();
  final _defilement = ScrollController();
  Timer? _minuterie;

  SearchPage? _page;

  /// Carrousels d'exploration : domaine → premières notices. Chargés UNE fois
  /// par ouverture de l'écran et gardés en mémoire — refaire les requêtes à
  /// chaque retour de fiche ferait payer plusieurs fois la même page.
  final Map<String, List<SearchHit>> _parDomaine = {};
  List<String> _domaines = [];
  bool _explorationChargee = false;
  bool _explorationEnCours = false;

  bool _chargement = false;
  bool _chargeSuite = false;
  String? _erreur;
  String _requeteCourante = '';

  /// Filtre par nature de document. `null` = tout.
  ///
  /// ⚠ L'API accepte `dans`, `category`, `language`, `year` et `recordType` ;
  /// l'app n'envoyait que la requête. Sur un dépôt universitaire, savoir
  /// distinguer une THÈSE d'un ouvrage est la première chose qu'on demande —
  /// et le fonds mesuré tient 74 thèses et 137 mémoires parmi 480 notices.
  /// On expose ce filtre-là, pas les cinq : un écran de recherche qui ouvre
  /// cinq menus avant la première frappe se referme.
  String? _type;

  @override
  void initState() {
    super.initState();
    _defilement.addListener(() {
      if (_defilement.position.pixels >= _defilement.position.maxScrollExtent - 200) {
        _suite();
      }
    });
  }

  @override
  void dispose() {
    _minuterie?.cancel();
    _controleur.dispose();
    _defilement.dispose();
    super.dispose();
  }

  /// Temporisation : une requête par frappe multiplierait la facture de
  /// données de l'usager par la longueur de son mot.
  void _saisie(String q) {
    _minuterie?.cancel();
    _minuterie = Timer(_delaiSaisie, () => _chercher(q));
  }

  Future<void> _chercher(String q, {bool force = false}) async {
    final requete = q.trim();
    // ⚠ Une requête VIDE avec un filtre actif est une demande légitime :
    // « montre-moi les thèses ». On n'efface donc l'écran que s'il n'y a ni
    // texte ni filtre — sinon on interroge, et le serveur rend la liste filtrée.
    if (requete.isEmpty && _type == null) {
      setState(() {
        _page = null;
        _erreur = null;
        _requeteCourante = '';
      });
      return;
    }
    if (!force && requete == _requeteCourante && _page != null) return;
    setState(() {
      _chargement = true;
      _erreur = null;
      _requeteCourante = requete;
    });
    try {
      final p = SearchPage.fromJson(await widget.search(requete, 1, _type));
      if (!mounted || _requeteCourante != requete) return;
      setState(() {
        _page = p;
        _chargement = false;
      });
    } catch (e) {
      if (!mounted || _requeteCourante != requete) return;
      setState(() {
        _chargement = false;
        _erreur = _messageReseau(e);
      });
    }
  }

  Future<void> _suite() async {
    final p = _page;
    if (p == null || !p.hasMore || _chargeSuite || _chargement) return;
    setState(() => _chargeSuite = true);
    try {
      final suivante = SearchPage.fromJson(await widget.search(_requeteCourante, p.page + 1, _type));
      if (!mounted) return;
      setState(() {
        _page = p.merge(suivante);
        _chargeSuite = false;
      });
    } catch (_) {
      // Échec sur la SUITE : on garde les résultats déjà obtenus. Les effacer
      // pour une page manquante punirait l'usager d'avoir fait défiler.
      if (mounted) setState(() => _chargeSuite = false);
    }
  }

  static String _messageReseau(Object e) {
    final t = e.toString();
    if (t.contains('SocketException') ||
        t.contains('TimeoutException') ||
        t.contains('Connection')) {
      return 'reseau';
    }
    return 'autre';
  }

  /// Charge l'exploration : un échantillon pour connaître les domaines du
  /// fonds, puis les premières notices de chacun.
  ///
  /// ⚠ LES DOMAINES NE SONT PAS CODÉS EN DUR. Chaque établissement catalogue
  /// comme il veut ; une liste écrite dans l'app serait juste pour celui sur
  /// lequel on l'a écrite et fausse pour tous les autres. On les DÉDUIT d'un
  /// échantillon, par fréquence.
  ///
  /// ⚠ ET ON BORNE : un échantillon, puis quatre domaines. Explorer coûte des
  /// requêtes, et un étudiant paie ses mégaoctets — ouvrir la recherche ne doit
  /// pas déclencher une rafale.
  Future<void> _chargerExploration() async {
    final explorer = widget.explorer;
    if (explorer == null || _explorationChargee || _explorationEnCours) return;
    _explorationEnCours = true;
    try {
      final echantillon = SearchPage.fromJson(await explorer(null, 40));
      final compte = <String, int>{};
      for (final h in echantillon.hits) {
        final c = (h.category ?? '').trim();
        if (c.isNotEmpty) compte[c] = (compte[c] ?? 0) + 1;
      }
      final ordre = compte.keys.toList()
        ..sort((a, b) => compte[b]!.compareTo(compte[a]!));
      _domaines = ordre.take(4).toList();
      for (final d in _domaines) {
        try {
          _parDomaine[d] = SearchPage.fromJson(await explorer(d, 10)).hits;
        } catch (_) {
          // Un domaine qui échoue ne fait pas tomber les autres : son
          // carrousel n'apparaît pas, le reste de l'écran tient.
        }
      }
      _explorationChargee = true;
    } catch (_) {
      // Hors ligne, ou serveur qui ne sait pas explorer : on retombera sur
      // l'invitation, jamais sur un écran en erreur — on venait chercher un
      // livre, pas un diagnostic réseau.
      _explorationChargee = true;
    } finally {
      _explorationEnCours = false;
      if (mounted) setState(() {});
    }
  }

  /// Les carrousels, un par domaine, avec « Tout voir ».
  Widget _exploration() {
    if (!_explorationChargee) {
      // Première ouverture : on lance le chargement sans bloquer la frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _chargerExploration());
      return const Center(child: CircularProgressIndicator());
    }
    final utiles = _domaines.where((d) => (_parDomaine[d] ?? []).isNotEmpty).toList();
    if (utiles.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Que cherchez-vous ?',
        message: 'Tapez un titre, un auteur ou un sujet. '
            'Les accents ne sont pas obligatoires.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final d in utiles) _carrousel(d, _parDomaine[d]!),
      ],
    );
  }

  Widget _carrousel(String domaine, List<SearchHit> hits) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    // Le domaine tel que l'établissement l'écrit, première
                    // lettre en capitale — on ne le traduit pas, on ne le
                    // reformule pas.
                    domaine[0].toUpperCase() + domaine.substring(1),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // « Tout voir » = la recherche filtrée sur ce domaine. Pas
                    // un second écran à tenir : le même, avec son filtre.
                    _controleur.text = domaine;
                    _chercher(domaine, force: true);
                  },
                  child: const Text('Tout voir'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 186,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: hits.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final h = hits[i];
                return SizedBox(
                  width: 104,
                  child: InkWell(
                    onTap: () => widget.openRecord(context, h),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CoverImage(
                            coverUrl: h.coverUrl,
                            titre: h.title,
                            auteur: h.author,
                            annee: h.publishYear,
                            domaine: h.category,
                            cache: widget.covers,
                            origine: widget.origine,
                            largeur: 104,
                            hauteur: 146,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          h.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rechercher')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controleur,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _saisie,
              onSubmitted: (q) {
                _minuterie?.cancel();
                _chercher(q);
              },
              decoration: InputDecoration(
                hintText: 'Titre, auteur, sujet…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _controleur.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controleur.clear();
                          _chercher('');
                        },
                      ),
              ),
            ),
          ),
          _barreDeTypes(),
          Expanded(child: _corps()),
        ],
      ),
    );
  }

  Widget _corps() {
    if (_erreur == 'reseau') {
      // On DIT que le réseau manque, et ce qui reste possible sans lui.
      return EmptyState(
        icon: Icons.wifi_off,
        title: 'La recherche a besoin du réseau',
        message: 'Le catalogue est trop volumineux pour tenir dans le téléphone. '
            'Vos prêts et vos documents téléchargés restent consultables hors connexion.',
        action: FilledButton(
          onPressed: () => _chercher(_requeteCourante),
          child: const Text('Réessayer'),
        ),
      );
    }
    if (_erreur != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Recherche impossible',
        message: 'La bibliothèque n’a pas pu répondre. Réessayez dans un instant.',
        action: FilledButton(
          onPressed: () => _chercher(_requeteCourante),
          child: const Text('Réessayer'),
        ),
      );
    }
    if (_chargement) return const Center(child: CircularProgressIndicator());

    final p = _page;
    if (p == null) {
      // ⚠ UN CHAMP VIDE N'EST PAS UNE INVITATION SUFFISANTE. « Que cherchez-vous ? »
      // suppose qu'on sache déjà quoi demander — or on vient souvent voir ce
      // qu'il y a. Quand le serveur sait explorer, on MONTRE le fonds ; sinon
      // on garde l'invitation plutôt qu'un bloc vide.
      if (widget.explorer != null) return _exploration();
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Que cherchez-vous ?',
        message: 'Tapez un titre, un auteur ou un sujet. '
            'Les accents ne sont pas obligatoires.',
      );
    }
    if (p.hits.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'Aucun résultat',
        message: 'Aucun document ne correspond à « $_requeteCourante ». '
            'Essayez moins de mots, ou une autre orthographe.',
      );
    }

    return ListView.builder(
      controller: _defilement,
      itemCount: p.hits.length + 1,
      itemBuilder: (context, i) {
        if (i == p.hits.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _chargeSuite
                  ? const CircularProgressIndicator()
                  : Text(
                      p.hasMore
                          ? 'Faites défiler pour voir la suite'
                          : '${p.totalHits} résultat${p.totalHits > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 12, color: context.gafeso.texteSecondaire),
                    ),
            ),
          );
        }
        final h = p.hits[i];
        return ListTile(
          leading: CoverImage(
            coverUrl: h.coverUrl,
            titre: h.title,
            // Dans une liste, la couverture est SEULE à identifier : elle garde
            // son auteur, et sa teinte dit le domaine d'un coup d'œil.
            auteur: h.author,
            annee: h.publishYear,
            domaine: h.category,
            cache: widget.covers,
            origine: widget.origine,
          ),
          title: Text(h.title),
          subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle),
          trailing: h.category == null ? null : Text(h.category!, style: const TextStyle(fontSize: 11)),
          onTap: () => widget.openRecord(context, h),
        );
      },
    );
  }

  /// Filtre par nature de document.
  ///
  /// ⚠ Posé SOUS le champ et non dans un menu : sur un dépôt universitaire,
  /// « je cherche une thèse » est une intention de départ, pas un raffinement
  /// d'après-coup. Un filtre qu'il faut aller ouvrir n'est pas utilisé.
  ///
  /// Changer de filtre relance la recherche courante — y compris quand elle est
  /// vide : le serveur répond alors la liste filtrée, ce qui permet de
  /// PARCOURIR les thèses sans rien taper.
  Widget _barreDeTypes() {
    const types = <(String?, String)>[
      (null, 'Tout'),
      ('these', 'Thèses'),
      ('memoire', 'Mémoires'),
      ('ouvrage', 'Ouvrages'),
      ('publication', 'Publications'),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final (valeur, libelle) in types)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(libelle),
                selected: _type == valeur,
                onSelected: (_) {
                  if (_type == valeur) return;
                  setState(() => _type = valeur);
                  _chercher(_controleur.text, force: true);
                },
              ),
            ),
        ],
      ),
    );
  }

}
