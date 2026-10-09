import 'package:flutter/material.dart';

import '../session/progress_store.dart';

import '../theme/gafeso_theme.dart';

import '../api/gafeso_api.dart';
import '../cache/cover_cache.dart';
import '../models/catalog.dart';
import '../widgets/cover_image.dart';
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
    this.covers,
    this.origine,
    this.circulation = true,
    this.estLocal = false,
    this.progression,
  });

  /// L'établissement a-t-il une circulation physique ?
  ///
  /// ⚠ Par défaut `true` : tant qu'on ne sait pas, on montre tout. Une
  /// bibliothèque NUMÉRIQUE n'a ni exemplaire ni comptoir — y afficher
  /// « Aucun exemplaire physique » serait exact et inutile, et un bouton
  /// « Réserver » promettrait une file d'attente qui n'existe pas.
  final bool circulation;

  /// Le document est-il déjà sur cet appareil ? Décide le badge « Disponible
  /// hors ligne » et le libellé du bouton principal.
  final bool estLocal;

  /// Où en est la lecture SUR CET APPAREIL. `null` = on ne sait pas, et on
  /// n'affiche alors aucun nombre de pages : la notice ne le porte pas.
  final Progression? progression;

  /// Cache des couvertures (optionnel : sans lui, substitut, aucun réseau).
  final CoverCache? covers;
  final String? origine;

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
    CoverCache? covers,
    String? origine,
    bool circulation = true,
    bool estLocal = false,
    Progression? progression,
  }) =>
      RecordScreen(
        key: key,
        recordId: recordId,
        titleHint: titleHint,
        fetchRecord: api.catalogRecord,
        placeHold: api.placeHold,
        onOpenDigital: onOpenDigital,
        covers: covers,
        origine: origine,
        circulation: circulation,
        estLocal: estLocal,
        progression: progression,
      );

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  bool _resumeDeplie = false;

  /// Ce que l'APPAREIL sait de ce document : est-il déjà là, et où en est la
  /// lecture. Renseigné par l'appelant ; `null` quand on ne sait pas — et on ne
  /// devine pas.
  Progression? get _progressionLocale => widget.progression;
  bool get _estLocal => widget.estLocal;

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ⚠ GRANDE, et pas par goût : à 72×100 la couverture composée ne
            // tenait que son initiale. C'est à partir de 120 dp de haut que le
            // titre et l'auteur s'y lisent, et c'est là qu'elle cesse d'être un
            // ornement pour devenir ce qui identifie le document.
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CoverImage(
                coverUrl: n.coverUrl,
                titre: n.title,
                auteur: n.author,
                type: n.typeLisible,
                annee: n.publishYear,
                domaine: n.category,
                // L'auteur est juste à droite : l'imprimer ici le montrerait
                // deux fois.
                avecAuteur: false,
                cache: widget.covers,
                origine: widget.origine,
                largeur: 118,
                hauteur: 164,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: const TextStyle(
                        fontSize: 21, fontWeight: FontWeight.bold, height: 1.25),
                  ),
                  const SizedBox(height: 8),
                  _badges(n),
                ],
              ),
            ),
          ],
        ),

        // Sous-titre : souvent la précision qui distingue deux travaux au titre
        // proche. Le jeter revient à afficher deux notices identiques.
        if ((n.titleComplement ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            n.titleComplement!,
            style: TextStyle(fontSize: 16, color: context.couleurs.onSurface, height: 1.3),
          ),
        ],

        const SizedBox(height: 10),
        _contributions(n),

        const SizedBox(height: 6),
        _ligneEdition(n),
        if (n.provenance != null) ...[
          const SizedBox(height: 12),
          _bandeauProvenance(n.provenance!),
        ],

        if (n.estTravailUniversitaire &&
            (n.defenseUniversity != null || n.defensePlace != null)) ...[
          const SizedBox(height: 16),
          _blocSoutenance(n),
        ],

        if (n.summary != null && n.summary!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          _resume(n.summary!.trim()),
        ],

        if (n.keywords.isNotEmpty) ...[
          const SizedBox(height: 16),
          _motsCles(n.keywords),
        ],

        if (n.hasDigitalCopy) ...[
          const SizedBox(height: 20),
          _carteNumerique(context, n),
        ],

        if (widget.circulation) ...[
          const SizedBox(height: 20),
          Text('Exemplaires', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (n.items.isEmpty)
          Text(
            'Aucun exemplaire physique pour cette notice.',
            style: TextStyle(fontSize: 13, color: context.gafeso.texteSecondaire),
          )
        else
          ...n.items.map((i) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  i.available ? Icons.check_circle_outline : Icons.remove_circle_outline,
                  color: i.available ? context.gafeso.succes : context.gafeso.avertissement,
                ),
                title: Text(i.statusLabel),
                // ⚠ « Rayon · Cote » NOMMÉS, et seulement là où il y a un
                // comptoir : ce bloc entier est déjà conditionné à la
                // circulation. Sans les mots, « Magasin · DRO DRO » ne dit pas
                // à l'étudiant OÙ aller ni QUOI demander — c'est précisément
                // l'information qui lui manque devant les rayonnages.
                subtitle: Text(
                  [
                    if ((i.location ?? '').isNotEmpty) 'Rayon ${i.location}',
                    if ((i.callNumber ?? '').isNotEmpty) 'Cote ${i.callNumber}',
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12),
                ),
              )),

        const SizedBox(height: 20),
        if (n.availableCount > 0)
          // Disponible : on n'offre PAS de réserver. Envoyer attendre quelqu'un
          // qui peut emprunter tout de suite serait absurde.
          Card(
            color: context.gafeso.succesFond,
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

        _details(n),
      ],
    );
  }

  /// Carte du document numérique. Elle ne dit que ce qui est VRAI de CE
  /// document : le lecteur décide sur ce qu'il lit, et une promesse de lecture
  /// hors connexion qui finit en refus lui coûte un trajet ou des données.
  ///
  /// Trois cas, et pas un de moins — c'est la réponse qui les distingue :
  ///   - embargo en cours : le fichier ne sortira pas avant la date, et on la
  ///     donne. La notice reste citable, ce qui est l'objet du dépôt ;
  ///   - PDF hors embargo : le seul cas où « hors connexion » est tenable,
  ///     `myDocuments` ne descendant que le PDF ;
  ///   - tout autre format (EPUB…) : le document existe, mais il se consulte
  ///     depuis le site. On le dit au lieu de le laisser croire.
  Widget _carteNumerique(BuildContext context, RecordDetail n) {
    final maintenant = DateTime.now();
    final format = (n.digitalFormat ?? '').toUpperCase();

    if (n.aUnEmbargoActif(maintenant)) {
      return Card(
        color: context.gafeso.avertissementFond,
        child: ListTile(
          leading: const Icon(Icons.lock_clock_outlined),
          title: const Text('Document sous embargo'),
          subtitle: Text(
            'Le texte intégral sera accessible à partir du '
            '${_jour(n.embargoUntil!)}. La notice reste citable.',
          ),
        ),
      );
    }

    if (n.estTelechargeable(maintenant)) {
      // ⚠ UN BOUTON, PAS UNE CARTE À TOUCHER. Le geste principal de cette fiche
      // est d'emporter le document ; une carte d'information cliquable ne se
      // lit pas comme une action, et c'est le défaut que Jean nomme « plate ».
      // Le libellé dit ce qui va se passer : LIRE si le document est déjà là,
      // TÉLÉCHARGER sinon. « Ouvrir » couvrirait les deux et n'informerait sur
      // aucun — et sur une connexion comptée, savoir si un geste va coûter des
      // mégaoctets n'est pas un détail.
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: widget.onOpenDigital == null
              ? null
              : () => widget.onOpenDigital!(context, n),
          icon: Icon(_estLocal ? Icons.menu_book_outlined : Icons.download_outlined),
          label: Text(_estLocal ? 'Lire hors ligne' : 'Télécharger'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Card(
      color: context.gafeso.infoFond,
      child: ListTile(
        leading: const Icon(Icons.menu_book_outlined),
        title: Text('Document numérique disponible ($format)'),
        subtitle: const Text(
          'Consultable depuis le site de la bibliothèque. '
          'La lecture hors connexion ne prend en charge que le PDF.',
        ),
      ),
    );
  }

  /// Même format que l'espace lecteur : JJ/MM/AAAA.
  static String _jour(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }


  /// Bandeau de provenance — P7-3 : « ce qui arrive par moissonnage reste
  /// marqué comme tel ».
  ///
  /// Le serveur sert cette clé à tous, membre ou non. Elle répond à la même
  /// question que la carte du document numérique : QU'EST-CE QUE ce document ?
  /// Une notice venue d'une autre école qui se présenterait comme catalogée ici
  /// est exactement le faux que la décision interdit — et il ne dépend pas de
  /// qui regarde. Le lien n'est pas rendu cliquable : ouvrir un navigateur
  /// demanderait une dépendance que l'app n'a pas, et un lien affiché reste
  /// vrai.
  /// Badges de la fiche — **seulement ce que la notice porte vraiment**.
  ///
  /// ⚠ Pas de badge « 240 pages » quand on ne connaît pas le nombre de pages :
  /// la notice ne le donne pas, et seul un document DÉJÀ ouvert sur cet appareil
  /// nous l'apprend. Un badge absent vaut mieux qu'un badge plausible.
  Widget _badges(RecordDetail n) {
    final p = _progressionLocale;
    final items = <(String, bool)>[
      if ((n.typeLisible ?? '').isNotEmpty) (n.typeLisible!, false),
      if (n.publishYear != null) ('${n.publishYear}', false),
      if (p != null) ('${p.pages} pages', false),
      if (_estLocal) ('Disponible hors ligne', true),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (texte, fort) in items)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: fort ? context.gafeso.succesFond : context.gafeso.infoFond,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              texte,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fort ? context.gafeso.surSucces : context.gafeso.surInfo,
              ),
            ),
          ),
      ],
    );
  }

  /// Résumé repliable.
  ///
  /// ⚠ Le seuil est en LIGNES rendues, pas en caractères : un résumé de 300
  /// signes tient en quatre lignes sur une tablette et en douze sur un écran
  /// étroit. On replie à partir de cinq lignes effectives, et « Voir plus »
  /// n'apparaît que s'il y a vraiment quelque chose de caché — un bouton qui
  /// ne révèle rien use la confiance.
  Widget _resume(String texte) => LayoutBuilder(
        builder: (ctx, bornes) {
          const style = TextStyle(fontSize: 14, height: 1.45);
          final tp = TextPainter(
            text: TextSpan(text: texte, style: style),
            maxLines: 5,
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: bornes.maxWidth);
          final deborde = tp.didExceedMaxLines;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                texte,
                style: style,
                maxLines: _resumeDeplie || !deborde ? null : 5,
                overflow: _resumeDeplie || !deborde
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
              ),
              if (deborde)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() => _resumeDeplie = !_resumeDeplie),
                  child: Text(_resumeDeplie ? 'Voir moins' : 'Voir plus'),
                ),
            ],
          );
        },
      );

  Widget _bandeauProvenance(Provenance p) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.gafeso.infoFond,
          border: Border(left: BorderSide(color: context.gafeso.info, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.hub_outlined, size: 16, color: context.gafeso.surInfo),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Notice moissonnée — ${p.sourceName}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.gafeso.surInfo,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Cette notice provient d’un autre établissement ; elle n’a pas été '
              'catalogée ici.',
              style: TextStyle(fontSize: 12, color: context.gafeso.surInfo),
            ),
            if (p.lien != null && p.lien!.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(
                p.lien!,
                style: TextStyle(fontSize: 12, color: context.couleurs.primary),
              ),
            ],
          ],
        ),
      );


  /// Qui a écrit, et qui a dirigé.
  ///
  /// ⚠ `author` seul est une dénormalisation du premier auteur principal. Sur
  /// un dépôt universitaire, la DIRECTION est une entrée de recherche à part
  /// entière — 211 des 480 notices mesurées en portent une, et l'app n'en
  /// montrait aucune. Repli sur `author` si le serveur ne sert pas la liste
  /// (réponse ancienne), pour ne jamais afficher moins qu'avant.
  Widget _contributions(RecordDetail n) {
    if (n.contributors.isEmpty) {
      return n.author == null
          ? const SizedBox.shrink()
          : Text(n.author!, style: TextStyle(fontSize: 16, color: context.couleurs.onSurface));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in n.contributors)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  style: TextStyle(
                    fontSize: c.estDirection ? 14 : 16,
                    color: c.estDirection
                        ? context.gafeso.texteSecondaire
                        : context.couleurs.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    c.roleLisible,
                    style: TextStyle(fontSize: 11, color: context.gafeso.texteSecondaire),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Type de document, éditeur, ville, année, catégorie — sur une ligne.
  /// La ville d'édition ne vaut qu'accolée à l'éditeur : « Presses — Ouaga ».
  Widget _ligneEdition(RecordDetail n) {
    final editeur = [n.publisher, n.publicationCity]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final parts = [
      if (editeur.isNotEmpty) editeur,
      n.publishYear?.toString(),
      n.category,
    ].whereType<String>().where((s) => s.isNotEmpty).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ⚠ LA PASTILLE DE TYPE A DÉMÉNAGÉ, elle n'a pas disparu. Elle vit
        // désormais dans la rangée de badges, sous le titre — et la laisser ici
        // AUSSI affichait « Ouvrage » deux fois sur la même fiche, à trois
        // centimètres d'écart. C'est un test qui l'a vu, pas une relecture.
        Expanded(
          child: Text(
            parts.join(' · '),
            style: TextStyle(fontSize: 13, color: context.gafeso.texteSecondaire),
          ),
        ),
      ],
    );
  }

  /// Où le travail a été soutenu — la raison d'être d'un dépôt de thèses.
  Widget _blocSoutenance(RecordDetail n) {
    final lieu = [n.defenseUniversity, n.defensePlace]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.gafeso.infoFond,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.school_outlined, size: 18, color: context.gafeso.surInfo),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${n.typeLisible ?? "Travail"} soutenu',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.gafeso.surInfo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(lieu, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Mots-clés d'indexation : ce par quoi on retrouve un sujet.
  Widget _motsCles(List<String> mots) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final m in mots)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.gafeso.infoFond,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.couleurs.outlineVariant),
              ),
              child: Text(m, style: const TextStyle(fontSize: 12)),
            ),
        ],
      );

  /// Détails bibliographiques de bas de fiche.
  ///
  /// ⚠ La LANGUE n'est affichée que si elle n'est pas le français : les 480
  /// notices mesurées sont toutes en `fr`, et répéter « Français » sur chacune
  /// ajoute une ligne à toutes les fiches sans jamais rien distinguer. Le jour
  /// où un fonds en portera d'autres, l'information reparaîtra d'elle-même.
  Widget _details(RecordDetail n) {
    final lignes = <(String, String)>[
      if ((n.isbn ?? '').trim().isNotEmpty) ('ISBN', n.isbn!),
      if ((n.language ?? '').isNotEmpty && n.language!.toLowerCase() != 'fr')
        ('Langue', n.language!),
    ];
    if (lignes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text('Détails', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (libelle, valeur) in lignes)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    libelle,
                    style: TextStyle(fontSize: 13, color: context.gafeso.texteSecondaire),
                  ),
                ),
                Expanded(child: Text(valeur, style: const TextStyle(fontSize: 13))),
              ],
            ),
          ),
      ],
    );
  }

}
