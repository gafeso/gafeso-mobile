import 'dart:async';

import 'package:flutter/material.dart';

import '../api/gafeso_api.dart';
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
  });

  /// Injectées en fonctions : `testWidgets` tourne en horloge simulée, où une
  /// E/S réseau réelle ne se termine jamais pendant les `pump`.
  final Future<Object> Function(String q, int page) search;
  final void Function(BuildContext context, SearchHit hit) openRecord;

  static SearchScreen from({Key? key, required GafesoApi api, required void Function(BuildContext, SearchHit) openRecord}) =>
      SearchScreen(
        key: key,
        search: (q, page) => api.searchCatalog(q, page: page),
        openRecord: openRecord,
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
  bool _chargement = false;
  bool _chargeSuite = false;
  String? _erreur;
  String _requeteCourante = '';

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

  Future<void> _chercher(String q) async {
    final requete = q.trim();
    if (requete.isEmpty) {
      setState(() {
        _page = null;
        _erreur = null;
        _requeteCourante = '';
      });
      return;
    }
    setState(() {
      _chargement = true;
      _erreur = null;
      _requeteCourante = requete;
    });
    try {
      final p = SearchPage.fromJson(await widget.search(requete, 1));
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
      final suivante = SearchPage.fromJson(await widget.search(_requeteCourante, p.page + 1));
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
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
            ),
          );
        }
        final h = p.hits[i];
        return ListTile(
          title: Text(h.title),
          subtitle: h.subtitle.isEmpty ? null : Text(h.subtitle),
          trailing: h.category == null ? null : Text(h.category!, style: const TextStyle(fontSize: 11)),
          onTap: () => widget.openRecord(context, h),
        );
      },
    );
  }
}
