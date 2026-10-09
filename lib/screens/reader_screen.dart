import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../session/progress_store.dart';
import '../theme/gafeso_theme.dart';

/// Écran de lecture : hôte de la **PlatformView native**. Tout ce qui touche au
/// déchiffrement, à la vérification de licence et au rendu se passe côté natif —
/// aucune page ne remonte vers Dart. `FLAG_SECURE` est posé sur la fenêtre par
/// `MainActivity`, et cet écran n'y touche pas.
///
/// Dart ne reçoit du lecteur qu'une chose : **le numéro de la page affichée**.
/// Il la range dans le coffre local et ne l'envoie nulle part — voir
/// `ProgressStore` et `test/progression_locale_test.dart`.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.title,
    required this.params,
    required this.docId,
    this.progression,
    this.pageDepart = 0,
    this.channel = const MethodChannel('com.gafeso/reader'),
    this.vueNative,
  });

  final String title;
  final Map<String, dynamic> params;
  final String docId;

  /// Injectable pour les tests ; sinon le coffre réel.
  final ProgressStore? progression;

  /// Page à rouvrir, lue sur l'appareil par l'appelant.
  final int pageDepart;

  final MethodChannel channel;

  /// Injectable : les tests de widget ne peuvent pas monter une PlatformView
  /// Android. Sans cette porte, cet écran serait intestable.
  final Widget? vueNative;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final ProgressStore _store = widget.progression ?? ProgressStore();
  ModeLecture _mode = ModeLecture.classique;
  int _page = 0;
  int _pages = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.pageDepart;
    widget.channel.setMethodCallHandler(_duNatif);
  }

  @override
  void dispose() {
    widget.channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _duNatif(MethodCall call) async {
    if (call.method != 'page') return null;
    final a = (call.arguments as Map).cast<String, dynamic>();
    final index = (a['index'] as num?)?.toInt() ?? 0;
    final total = (a['total'] as num?)?.toInt() ?? 0;
    if (mounted) setState(() { _page = index; _pages = total; });
    // ⚠ ÉCRIT SUR L'APPAREIL, ET NULLE PART AILLEURS.
    await _store.noter(docId: widget.docId, page: index, pages: total);
    return null;
  }

  Future<void> _changerMode(ModeLecture m) async {
    setState(() => _mode = m);
    try {
      await widget.channel.invokeMethod('setMode', {'mode': m.cle});
    } on MissingPluginException {
      // Hors appareil (tests) : l'écran reste cohérent, rien ne lève.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _pages > 0
        ? Progression(docId: widget.docId, page: _page, pages: _pages, majAt: DateTime(2000))
        : null;

    return Scaffold(
      backgroundColor: _mode.fond(context),
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          PopupMenuButton<ModeLecture>(
            tooltip: 'Mode de lecture',
            icon: const Icon(Icons.contrast),
            initialValue: _mode,
            onSelected: _changerMode,
            itemBuilder: (_) => [
              for (final m in ModeLecture.values)
                PopupMenuItem(value: m, child: Text(m.libelle)),
            ],
          ),
        ],
        // La progression tient dans la barre : une ligne de texte et un filet.
        // Pas de panneau, pas de bouton — on lit, on ne pilote pas un tableau
        // de bord.
        bottom: p == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(26),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        'Page ${p.pageLisible} / ${p.pages}',
                        style: TextStyle(fontSize: 12, color: context.couleurs.onPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: p.part,
                            minHeight: 4,
                            backgroundColor:
                                context.couleurs.onPrimary.withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation(GafesoMarque.orange),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${p.pourcent} %',
                        style: TextStyle(fontSize: 12, color: context.couleurs.onPrimary),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      body: widget.vueNative ??
          AndroidView(
            viewType: 'gafeso-pdf-reader',
            creationParams: {
              ...widget.params,
              'pageDepart': widget.pageDepart,
              'mode': _mode.cle,
            },
            creationParamsCodec: const StandardMessageCodec(),
          ),
    );
  }
}

/// Les trois modes offerts, et **rien d'autre**.
///
/// ⚠ PAS DE RÉGLAGE DE POLICE NI D'INTERLIGNE. Un PDF est une page déjà
/// composée : un curseur de taille de texte n'y changerait rien. Afficher un
/// réglage sans effet est pire que ne rien offrir — l'usager essaie, constate
/// que rien ne bouge, et conclut que l'application est cassée.
enum ModeLecture {
  classique('classique', 'Classique'),
  sepia('sepia', 'Sépia'),
  nuit('nuit', 'Nuit');

  const ModeLecture(this.cle, this.libelle);

  final String cle;
  final String libelle;

  /// Fond de l'écran derrière la page. Les mêmes valeurs que `ModeLecture.kt`
  /// côté natif — c'est la vue native qui peint la page, cet écran peint ce qui
  /// l'entoure, et un écart se verrait comme une bande d'une autre couleur.
  Color fond(BuildContext context) => fondsModesLecture[cle]!;
}
