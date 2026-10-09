import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Outils partagés des tests de lisibilité.
///
/// ⚠ UNE SEULE IMPLÉMENTATION, et c'est le point. La formule de contraste
/// existait en deux copies (palette, carte de lecteur) et une troisième
/// arrivait avec les couvertures. Trois copies d'une formule, ce sont trois
/// occasions qu'elle diverge — et une formule fausse ne fait pas échouer les
/// tests : elle les fait TOUS passer.

double _canal(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double luminance(Color c) =>
    0.2126 * _canal(c.r) + 0.7152 * _canal(c.g) + 0.0722 * _canal(c.b);

/// Rapport de contraste WCAG 2.1 entre deux couleurs opaques.
double contraste(Color a, Color b) {
  final la = luminance(a), lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Couleur **réellement peinte** d'un texte à l'écran.
///
/// ⚠ Pas la couleur déclarée dans un jeton : celle que le rendu a retenue.
/// La distinction a déjà coûté un nom de lecteur invisible sur une carte restée
/// blanche en mode sombre — le jeton était juste, l'écran ne s'en servait pas.
///
/// Balaie les paragraphes, puis les champs éditables : un `SelectableText` ne
/// peint pas par un `RenderParagraph`, et ne chercher que les paragraphes ferait
/// échouer le test pour une raison de plomberie, pas de lisibilité.
Color couleurPeinte(WidgetTester t, String texte) {
  for (final p in t.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    if (p.text.toPlainText().contains(texte)) return p.text.style!.color!;
  }
  for (final e in t.widgetList<EditableText>(find.byType(EditableText))) {
    if (e.controller.text.contains(texte)) return e.style.color!;
  }
  throw StateError('texte « $texte » introuvable à l’écran');
}
