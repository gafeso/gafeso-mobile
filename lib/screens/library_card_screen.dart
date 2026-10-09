import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../theme/gafeso_theme.dart';
import 'package:flutter/services.dart';

import '../api/gafeso_api.dart';
import '../cache/offline_cache.dart';
import '../models/library_card.dart';
import '../widgets/freshness_banner.dart';

/// Ma carte de lecteur — le code-barres que la douchette du comptoir lit.
///
/// ── Pourquoi cet écran fonctionne hors ligne par construction ─────────────
/// C'est son cas d'usage EXACT : le comptoir d'une bibliothèque sans wifi. Un
/// écran de carte qui exigerait le réseau serait inutilisable précisément là où
/// il sert. Le code-barres est mémorisé et affiché sans aucun appel.
///
/// ── Et pourquoi il n'affiche JAMAIS de bandeau « daté » ───────────────────
/// Le code-barres d'un adhérent est immuable. Signaler qu'il date de trois
/// semaines ferait douter le bibliothécaire sans aucune raison — et douter d'un
/// code-barres, c'est refuser un prêt. Voir `Volatility.carte`.
///
/// ── Luminosité ───────────────────────────────────────────────────────────
/// Poussée au maximum à l'ouverture, restaurée à la sortie. Une douchette lit
/// mal un écran sombre, et l'usager ne doit pas avoir à trafiquer ses réglages
/// devant la file d'attente. La valeur porte sur la FENÊTRE, pas sur le réglage
/// système : elle ne survit pas à l'écran.
class LibraryCardScreen extends StatefulWidget {
  const LibraryCardScreen({
    super.key,
    required this.fetchCard,
    required this.cache,
    this.channel = const MethodChannel('com.gafeso/device'),
  });

  final Future<Object> Function() fetchCard;
  final OfflineCache cache;
  final MethodChannel channel;

  static LibraryCardScreen from({
    Key? key,
    required GafesoApi api,
    required OfflineCache cache,
  }) =>
      LibraryCardScreen(key: key, fetchCard: api.readerCard, cache: cache);

  @override
  State<LibraryCardScreen> createState() => _LibraryCardScreenState();
}

class _LibraryCardScreenState extends State<LibraryCardScreen> {
  Cached<LibraryCard> _carte = const Cached<LibraryCard>();
  bool _chargement = true;

  @override
  void initState() {
    super.initState();
    _eclairer(1.0);
    _charger();
  }

  @override
  void dispose() {
    // Restauration systématique : laisser l'écran à fond viderait la batterie
    // d'un appareil qu'on n'a pas le droit de maltraiter.
    _eclairer(null);
    super.dispose();
  }

  Future<void> _eclairer(double? v) async {
    try {
      await widget.channel.invokeMethod('setBrightness', {'value': v});
    } catch (_) {
      // Canal absent (test, plateforme sans implémentation) : la carte reste
      // parfaitement utilisable, simplement moins lumineuse. Ce n'est pas une
      // raison d'échouer.
    }
  }

  Future<void> _charger() async {
    final c = await loadCached<LibraryCard>(
      cache: widget.cache,
      resource: 'reader.card',
      fromJson: LibraryCard.fromJson,
      toJson: (v) => v.toJson(),
      fetch: () async => LibraryCard.fromJson(await widget.fetchCard()),
    );
    if (!mounted) return;
    setState(() {
      _carte = c;
      _chargement = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _carte.value;
    return Scaffold(
      backgroundColor: context.gafeso.carte,
      appBar: AppBar(title: const Text('Ma carte')),
      body: SafeArea(
        child: _chargement && c == null
            ? const Center(child: CircularProgressIndicator())
            : c == null
                ? EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'Carte pas encore disponible',
                    message: 'Connectez-vous une fois au réseau : votre carte '
                        'restera ensuite affichable hors connexion, au comptoir.',
                    action: FilledButton(
                      onPressed: _charger,
                      child: const Text('Réessayer'),
                    ),
                  )
                : _carteWidget(c),
      ),
    );
  }

  /// ⚠ LA CARTE EST UNE FEUILLE BLANCHE, DANS LES DEUX MODES — et tout ce qui
  /// s'y pose doit donc prendre une couleur de CARTE, pas une couleur de thème.
  ///
  /// Trouvé en mode sombre, sur capture : le nom du lecteur et son numéro
  /// n'avaient pas de couleur déclarée, héritaient donc de `onSurface` — clair
  /// sur fond sombre — et devenaient quasi invisibles sur le blanc de la carte.
  /// Le défaut est muet : l'écran s'affiche, le code-barres se lit, et c'est le
  /// nom qu'on présente au comptoir qui a disparu.
  ///
  /// Le `DefaultTextStyle` règle la question pour TOUT le contenu, y compris ce
  /// qu'on y ajoutera demain — là où corriger trois styles un à un laisse le
  /// quatrième se tromper.
  Widget _carteWidget(LibraryCard c) => DefaultTextStyle.merge(
        style: TextStyle(color: context.gafeso.surCarte),
        child: _contenuCarte(c),
      );

  Widget _contenuCarte(LibraryCard c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              c.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(c.category, style: TextStyle(fontSize: 14, color: context.gafeso.surCarteSecondaire)),
            const SizedBox(height: 32),
            // Symbologie donnée par le SERVEUR, jamais devinée.
            //
            // Une symbologie INCONNUE n'est pas rendue en Code 128 « au cas
            // où » : la carte paraîtrait normale et la douchette ne lirait
            // rien — l'échec le plus coûteux, celui qui ne dit pas son nom.
            // On affiche alors le code en clair et on explique, ce qui laisse
            // le bibliothécaire le saisir à la main.
            if (c.symbology == 'code128')
              // Fond blanc et marge : une douchette lit mal un code collé au
              // bord ou posé sur une couleur.
              Container(
                color: context.gafeso.carte,
                padding: const EdgeInsets.all(16),
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: c.barcode,
                  width: double.infinity,
                  height: 140,
                  drawText: false,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(16),
                color: context.gafeso.avertissementFond,
                child: Text(
                  'Cette bibliothèque utilise un format de code-barres que '
                  'l’application ne sait pas dessiner (« ${c.symbology} »). '
                  'Donnez le numéro ci-dessous au comptoir.',
                  // Ce bloc a son PROPRE fond : il garde sa propre couleur de
                  // texte, que le DefaultTextStyle de la carte ne doit pas
                  // écraser.
                  style: TextStyle(fontSize: 13, color: context.gafeso.surAvertissement),
                ),
              ),
            const SizedBox(height: 16),
            // Le code EN CLAIR sous le trait : si la douchette échoue — écran
            // rayé, mauvaise lumière — le bibliothécaire le saisit à la main
            // au lieu de renvoyer l'étudiant.
            SelectableText(
              c.barcode,
              style: const TextStyle(
                fontSize: 20,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Présentez ce code au comptoir.',
              style: TextStyle(fontSize: 13, color: context.gafeso.surCarteSecondaire),
            ),
          ],
        ),
      );
}
