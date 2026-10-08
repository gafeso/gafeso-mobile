import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// IDENTITÉ VISUELLE — le SEUL endroit du code où une couleur est écrite.
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Le logo Gafeso est une maison dont le toit s'ouvre en livre : vert pour la
/// maison, orange pour les pages. L'application portait un bleu marine sans
/// rapport, et soixante-quatre couleurs écrites en dur dans les écrans.
///
/// ⚠ POURQUOI UN SEUL FICHIER. Une couleur écrite dans un écran est invisible
/// au thème : elle ne suit pas le mode sombre, elle ne se teste pas, et elle se
/// recopie. C'est ainsi que `Colors.black54` — correct sur fond clair — se
/// retrouvait sur dix-huit écrans, où le mode sombre l'aurait rendu illisible.
/// Un test (`test/couleurs_test.dart`) refuse désormais toute couleur littérale
/// hors d'ici.
///
/// ⚠ ET POURQUOI DES COUPLES, PAS DES COULEURS. Une couleur seule ne se juge
/// pas : c'est le COUPLE texte/fond qui est lisible ou non. Chaque couple
/// déclaré ici est éprouvé par calcul de contraste WCAG ≥ 4,5:1, avec un
/// contrôle négatif — blanc sur orange vaut 3,01:1 et DOIT faire échouer le
/// test. C'est la paire qu'on écrirait spontanément, et c'est celle qu'il faut
/// empêcher.

/// Les trois couleurs de la marque. Rien d'autre n'est « une couleur Gafeso ».
abstract final class GafesoMarque {
  /// Vert de la maison. `primary` vaut EXACTEMENT ceci, en clair comme en
  /// sombre pour les surfaces de marque (barre, boutons principaux, liens).
  static const vert = Color(0xFF1B5E3F);

  /// Orange des pages. Accent : badges, « hors ligne », progression, icônes
  /// actives.
  static const orange = Color(0xFFE07A2B);

  /// Orange foncé. États appuyés, et accent du mode sombre.
  ///
  /// ⚠ NE PORTE PAS DE TEXTE BLANC (4,05:1 — sous le seuil AA, comme l'orange
  /// clair à 3,01:1). Il sert de teinte d'appui et de filet, jamais de fond de
  /// texte clair.
  static const orangeFonce = Color(0xFFC4641F);
}

/// Couleurs de SENS, que `ColorScheme` ne nomme pas.
///
/// Material 3 donne `primary`, `error`, `surface`… mais rien pour « ce prêt est
/// en retard », « ce document est disponible hors ligne », « cette licence a
/// expiré ». Ces trois états existent dans le produit et ont besoin d'un fond,
/// d'une couleur de texte et d'un filet — en clair ET en sombre.
@immutable
class GafesoPalette extends ThemeExtension<GafesoPalette> {
  const GafesoPalette({
    required this.succes,
    required this.succesFond,
    required this.surSucces,
    required this.avertissement,
    required this.avertissementFond,
    required this.surAvertissement,
    required this.erreurFond,
    required this.surErreur,
    required this.info,
    required this.infoFond,
    required this.surInfo,
    required this.texteSecondaire,
    required this.carte,
    required this.surCarte,
    required this.surCarteSecondaire,
    required this.surCamera,
    required this.appuye,
  });

  /// Disponible, exemplaire présent, réservation prête, protection active.
  final Color succes;
  final Color succesFond;
  final Color surSucces;

  /// Licence expirée, prêt bientôt dû, hors ligne, session expirée. C'est la
  /// famille ORANGE de la marque : l'accent du logo sert à l'attention.
  final Color avertissement;
  final Color avertissementFond;
  final Color surAvertissement;

  /// Fond des blocs d'erreur (le texte prend `colorScheme.error`).
  final Color erreurFond;
  final Color surErreur;

  /// Blocs neutres : contributions, soutenance, résumé, vignette sans couverture.
  final Color info;
  final Color infoFond;
  final Color surInfo;

  /// Texte d'appoint (sous-titres, légendes). Remplace `Colors.black54`, qui
  /// disparaissait en mode sombre.
  final Color texteSecondaire;

  /// ⚠ FOND DE LA CARTE DE LECTEUR — BLANC, et c'est FONCTIONNEL : le code-barres
  /// doit être lu par une douchette au comptoir. Il ne suit donc PAS le mode
  /// sombre, délibérément.
  final Color carte;
  final Color surCarte;

  /// ⚠ Texte d'appoint SUR LA CARTE, et non sur une surface du thème.
  /// La carte reste blanche en mode sombre ; `texteSecondaire`, lui, s'éclaircit
  /// pour les fonds sombres et tombait alors à 2,25:1 sur ce blanc. Deux fonds
  /// différents veulent deux couleurs de texte : c'est le test de contraste qui
  /// l'a montré, pas la relecture.
  final Color surCarteSecondaire;

  /// Surimpression sur l'aperçu caméra (cadre de visée du QR). Le fond est une
  /// image vidéo, pas une surface du thème.
  final Color surCamera;

  /// État appuyé — l'orange foncé de la marque.
  final Color appuye;

  @override
  GafesoPalette copyWith({
    Color? succes,
    Color? succesFond,
    Color? surSucces,
    Color? avertissement,
    Color? avertissementFond,
    Color? surAvertissement,
    Color? erreurFond,
    Color? surErreur,
    Color? info,
    Color? infoFond,
    Color? surInfo,
    Color? texteSecondaire,
    Color? carte,
    Color? surCarte,
    Color? surCarteSecondaire,
    Color? surCamera,
    Color? appuye,
  }) =>
      GafesoPalette(
        succes: succes ?? this.succes,
        succesFond: succesFond ?? this.succesFond,
        surSucces: surSucces ?? this.surSucces,
        avertissement: avertissement ?? this.avertissement,
        avertissementFond: avertissementFond ?? this.avertissementFond,
        surAvertissement: surAvertissement ?? this.surAvertissement,
        erreurFond: erreurFond ?? this.erreurFond,
        surErreur: surErreur ?? this.surErreur,
        info: info ?? this.info,
        infoFond: infoFond ?? this.infoFond,
        surInfo: surInfo ?? this.surInfo,
        texteSecondaire: texteSecondaire ?? this.texteSecondaire,
        carte: carte ?? this.carte,
        surCarte: surCarte ?? this.surCarte,
        surCarteSecondaire: surCarteSecondaire ?? this.surCarteSecondaire,
        surCamera: surCamera ?? this.surCamera,
        appuye: appuye ?? this.appuye,
      );

  @override
  GafesoPalette lerp(ThemeExtension<GafesoPalette>? autre, double t) {
    if (autre is! GafesoPalette) return this;
    Color m(Color a, Color b) => Color.lerp(a, b, t)!;
    return GafesoPalette(
      succes: m(succes, autre.succes),
      succesFond: m(succesFond, autre.succesFond),
      surSucces: m(surSucces, autre.surSucces),
      avertissement: m(avertissement, autre.avertissement),
      avertissementFond: m(avertissementFond, autre.avertissementFond),
      surAvertissement: m(surAvertissement, autre.surAvertissement),
      erreurFond: m(erreurFond, autre.erreurFond),
      surErreur: m(surErreur, autre.surErreur),
      info: m(info, autre.info),
      infoFond: m(infoFond, autre.infoFond),
      surInfo: m(surInfo, autre.surInfo),
      texteSecondaire: m(texteSecondaire, autre.texteSecondaire),
      carte: m(carte, autre.carte),
      surCarte: m(surCarte, autre.surCarte),
      surCarteSecondaire: m(surCarteSecondaire, autre.surCarteSecondaire),
      surCamera: m(surCamera, autre.surCamera),
      appuye: m(appuye, autre.appuye),
    );
  }

  /// ⚠ Les couples éprouvés par le test de contraste. Déclarés ICI, à côté des
  /// couleurs : une liste tenue dans le fichier de test se serait désynchronisée
  /// au premier ajout, et le test aurait continué à passer en n'éprouvant plus
  /// rien.
  List<(String, Color, Color)> get couplesTexteFond => [
        ('texte d’appoint de la carte', surCarteSecondaire, carte),
        ('succès', surSucces, succesFond),
        ('avertissement', surAvertissement, avertissementFond),
        ('erreur', surErreur, erreurFond),
        ('information', surInfo, infoFond),
        ('carte de lecteur', surCarte, carte),
      ];
}

const _paletteClaire = GafesoPalette(
  succes: Color(0xFF14492F),
  succesFond: Color(0xFFDFF0E6),
  surSucces: Color(0xFF14492F),
  avertissement: Color(0xFF8A4A14),
  avertissementFond: Color(0xFFFDEEDF),
  surAvertissement: Color(0xFF6B3A10),
  erreurFond: Color(0xFFFCE9E8),
  surErreur: Color(0xFF6E1B16),
  info: Color(0xFF2F4152),
  infoFond: Color(0xFFE7EEF4),
  surInfo: Color(0xFF2F4152),
  texteSecondaire: Color(0xFF5A5F55),
  carte: Color(0xFFFFFFFF),
  surCarte: Color(0xFF1A1C1A),
  surCarteSecondaire: Color(0xFF5A5F55),
  surCamera: Color(0xFFFFFFFF),
  appuye: GafesoMarque.orangeFonce,
);

const _paletteSombre = GafesoPalette(
  succes: Color(0xFF8FD6AE),
  succesFond: Color(0xFF0E2E1D),
  surSucces: Color(0xFF8FD6AE),
  avertissement: Color(0xFFF5C08A),
  avertissementFond: Color(0xFF3A2410),
  surAvertissement: Color(0xFFF5C08A),
  erreurFond: Color(0xFF3A1512),
  surErreur: Color(0xFFFFB4AB),
  info: Color(0xFFB8CBDC),
  infoFond: Color(0xFF1A242E),
  surInfo: Color(0xFFB8CBDC),
  texteSecondaire: Color(0xFFA9AFA3),
  // ⚠ La carte reste BLANCHE en mode sombre : c'est une surface à scanner.
  carte: Color(0xFFFFFFFF),
  surCarte: Color(0xFF1A1C1A),
  // ⚠ Identique à la palette claire : le fond, lui, est resté blanc.
  surCarteSecondaire: Color(0xFF5A5F55),
  surCamera: Color(0xFFFFFFFF),
  appuye: GafesoMarque.orangeFonce,
);

/// `ColorScheme` clair. `fromSeed` donne l'harmonie Material 3 ; les rôles de
/// marque sont ensuite FIXÉS, parce qu'une graine ne rend jamais exactement la
/// couleur qu'on lui donne et que `primary` doit valoir `#1B5E3F` au bit près.
final _schemaClair = ColorScheme.fromSeed(
  seedColor: GafesoMarque.vert,
).copyWith(
  primary: GafesoMarque.vert,
  onPrimary: const Color(0xFFFFFFFF),
  primaryContainer: const Color(0xFFD7EBE0),
  onPrimaryContainer: const Color(0xFF0A2E1D),
  secondary: GafesoMarque.orange,
  // ⚠ PAS DE BLANC ICI. Blanc sur #E07A2B vaut 3,01:1 — sous AA. Le brun très
  // sombre tient 5,88:1 et c'est la seule raison de son existence.
  onSecondary: const Color(0xFF2B1200),
  secondaryContainer: const Color(0xFFFDEBDC),
  onSecondaryContainer: const Color(0xFF5A2D08),
  error: const Color(0xFFB3261E),
  onError: const Color(0xFFFFFFFF),
  surface: const Color(0xFFFBFDF9),
  onSurface: const Color(0xFF1A1C1A),
  onSurfaceVariant: const Color(0xFF44483F),
);

final _schemaSombre = ColorScheme.fromSeed(
  seedColor: GafesoMarque.vert,
  brightness: Brightness.dark,
).copyWith(
  // En sombre, le vert de marque sert de TEINTE, pas de fond : à 2,43:1 sur
  // #12140F il serait illisible. La barre garde le vert exact (voir plus bas) ;
  // les textes et icônes prennent cette version éclaircie.
  primary: const Color(0xFF7FD3A6),
  onPrimary: const Color(0xFF00391F),
  primaryContainer: GafesoMarque.vert,
  onPrimaryContainer: const Color(0xFFD7EBE0),
  secondary: const Color(0xFFF0A868),
  onSecondary: const Color(0xFF4A2000),
  // ⚠ PAS `orangeFonce` ICI : #FFE2C9 sur #C4641F ne vaut que 3,27:1. L'orange
  // foncé est une teinte d'appui, pas un fond de texte — en sombre non plus.
  secondaryContainer: const Color(0xFF5A2D08),
  onSecondaryContainer: const Color(0xFFFFD9B8),
  surface: const Color(0xFF12140F),
  onSurface: const Color(0xFFE2E3DE),
  onSurfaceVariant: const Color(0xFFC3C8BC),
);

ThemeData _construire(ColorScheme s, GafesoPalette p) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    extensions: [p],
    scaffoldBackgroundColor: s.surface,
    // ⚠ La barre porte le vert EXACT dans les deux modes : c'est l'élément de
    // marque, celui qu'on reconnaît avant d'avoir lu quoi que ce soit.
    appBarTheme: const AppBarTheme(
      backgroundColor: GafesoMarque.vert,
      foregroundColor: Color(0xFFFFFFFF),
      elevation: 0,
      centerTitle: false,
      // ⚠ La barre système est AU-DESSUS du vert. Sans cette ligne, Material
      // déduit le style des icônes de la couleur de SURFACE, pas de celle de
      // l'AppBar : en mode clair, l'heure et la batterie restaient sombres sur
      // le vert, à la limite du lisible. `light` désigne des icônes CLAIRES.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (e) => e.contains(WidgetState.pressed) ? p.appuye : s.primary,
        ),
        foregroundColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(s.primary)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(foregroundColor: WidgetStatePropertyAll(s.primary)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      // L'orange des pages pour la progression : c'est le geste du produit
      // (emporter un document), il mérite l'accent et non la couleur de fond.
      color: GafesoMarque.orange,
      linearTrackColor: s.surfaceContainerHighest,
    ),
    chipTheme: ChipThemeData(
      selectedColor: s.primaryContainer,
      checkmarkColor: s.onPrimaryContainer,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.inverseSurface,
      contentTextStyle: TextStyle(color: s.onInverseSurface),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant),
  );
}

ThemeData gafesoClair() => _construire(_schemaClair, _paletteClaire);
ThemeData gafesoSombre() => _construire(_schemaSombre, _paletteSombre);

/// Raccourci de lecture dans les écrans : `context.gafeso.succes`.
extension GafesoThemeContext on BuildContext {
  /// ⚠ REPLI PLUTÔT QUE `!`. Un widget de ce dépôt peut être monté sous un
  /// thème qui n'est pas le nôtre — un `MaterialApp` nu dans un test, un écran
  /// réutilisé ailleurs. Avec un `!`, il ne s'affichait pas « sans couleurs » :
  /// il LEVAIT, et soixante-dix tests sont passés d'un coup à « 0 widget
  /// trouvé », ce qui ne désigne jamais la vraie cause.
  ///
  /// Le repli suit la LUMINOSITÉ du thème hôte, pas une palette fixe : rendre
  /// la palette claire sous un thème sombre produirait du texte noir sur fond
  /// noir, soit le défaut qu'on vient de corriger partout.
  GafesoPalette get gafeso {
    final t = Theme.of(this);
    return t.extension<GafesoPalette>() ??
        (t.brightness == Brightness.dark ? _paletteSombre : _paletteClaire);
  }

  ColorScheme get couleurs => Theme.of(this).colorScheme;
}
