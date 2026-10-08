import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// L'IDENTITÉ, ÉPROUVÉE — contraste réel, et une seule source de couleur.
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Deux choses sont tenues ici, et aucune ne se vérifie à l'œil :
///
/// 1. **Chaque couple texte/fond atteint WCAG AA (4,5:1).** Pas « a l'air
///    lisible » : calculé. Le contrôle négatif est la pièce maîtresse — blanc
///    sur l'orange de la marque vaut 3,01:1, c'est la paire qu'on écrirait
///    spontanément, et ce test DOIT la refuser. Sans ce contrôle, une erreur de
///    formule rendrait tout conforme et le test applaudirait un écran illisible.
///
/// 2. **Aucune couleur littérale hors du fichier de thème.** Une couleur écrite
///    dans un écran ne suit pas le mode sombre et ne se teste pas : c'est ainsi
///    que `Colors.black54` s'était recopié sur dix-huit écrans.

// ── WCAG 2.1, relative luminance et rapport de contraste ────────────────────
double _canal(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _canal(c.r) + 0.7152 * _canal(c.g) + 0.0722 * _canal(c.b);

double contraste(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('la formule de contraste elle-même', () {
    // ⚠ Une formule fausse rendrait TOUT conforme. On l'ancre sur des valeurs
    // connues avant de s'en servir pour juger quoi que ce soit.
    test('ancrages connus', () {
      expect(contraste(const Color(0xFF000000), const Color(0xFFFFFFFF)),
          closeTo(21.0, 0.01));
      expect(contraste(const Color(0xFFFFFFFF), const Color(0xFFFFFFFF)),
          closeTo(1.0, 0.01));
      // Symétrique : l'ordre texte/fond ne change pas le rapport.
      expect(contraste(const Color(0xFF1B5E3F), const Color(0xFFFFFFFF)),
          closeTo(contraste(const Color(0xFFFFFFFF), const Color(0xFF1B5E3F)), 0.001));
    });
  });

  group('⚠ CONTRÔLE NÉGATIF — la paire interdite', () {
    test('blanc sur orange #E07A2B est REFUSÉ', () {
      final r = contraste(const Color(0xFFFFFFFF), GafesoMarque.orange);
      expect(r, lessThan(4.5),
          reason: 'si ceci passait, le test ne mesurerait pas ce qu’il croit');
      expect(r, closeTo(3.01, 0.02));
    });

    test('blanc sur orange foncé #C4641F est REFUSÉ aussi', () {
      // 4,05:1 — sous le seuil malgré l'apparence « assez sombre ».
      expect(contraste(const Color(0xFFFFFFFF), GafesoMarque.orangeFonce),
          lessThan(4.5));
    });

    test('l’orange ne porte JAMAIS de blanc dans le thème', () {
      for (final t in [gafesoClair(), gafesoSombre()]) {
        final s = t.colorScheme;
        // `onSecondary` est la couleur que Material pose SUR `secondary`.
        expect(contraste(s.onSecondary, s.secondary), greaterThanOrEqualTo(4.5),
            reason: 'onSecondary=${s.onSecondary} sur secondary=${s.secondary}');
      }
    });
  });

  group('tous les couples du thème atteignent AA', () {
    for (final (nom, theme) in [('clair', gafesoClair()), ('sombre', gafesoSombre())]) {
      final s = theme.colorScheme;
      final p = theme.extension<GafesoPalette>()!;

      final couples = <(String, Color, Color)>[
        ('onPrimary / primary', s.onPrimary, s.primary),
        ('onSecondary / secondary', s.onSecondary, s.secondary),
        ('onPrimaryContainer / primaryContainer', s.onPrimaryContainer, s.primaryContainer),
        ('onSecondaryContainer / secondaryContainer',
            s.onSecondaryContainer, s.secondaryContainer),
        ('onSurface / surface', s.onSurface, s.surface),
        ('onSurfaceVariant / surface', s.onSurfaceVariant, s.surface),
        ('onError / error', s.onError, s.error),
        ('texteSecondaire / surface', p.texteSecondaire, s.surface),
        ('primary (lien) / surface', s.primary, s.surface),
        // La barre porte le vert exact dans les deux modes : son texte est blanc.
        ('blanc / vert de la barre', const Color(0xFFFFFFFF), GafesoMarque.vert),
        ...p.couplesTexteFond,
      ];

      for (final (libelle, texte, fond) in couples) {
        test('[$nom] $libelle', () {
          expect(contraste(texte, fond), greaterThanOrEqualTo(4.5),
              reason: 'texte=$texte fond=$fond — ${contraste(texte, fond).toStringAsFixed(2)}:1');
        });
      }
    }
  });

  group('la marque est EXACTE', () {
    test('primary vaut #1B5E3F au bit près, en clair', () {
      // `ColorScheme.fromSeed` ne rend JAMAIS la graine telle quelle : elle
      // l'harmonise. Sans le `copyWith`, le vert du logo n'aurait jamais été
      // à l'écran, et personne ne l'aurait vu à l'œil nu.
      expect(gafesoClair().colorScheme.primary, GafesoMarque.vert);
    });

    test('la barre porte le vert exact dans les DEUX modes', () {
      for (final t in [gafesoClair(), gafesoSombre()]) {
        expect(t.appBarTheme.backgroundColor, GafesoMarque.vert);
      }
    });

    test('l’accent vaut #E07A2B en clair', () {
      expect(gafesoClair().colorScheme.secondary, GafesoMarque.orange);
    });

    test('⚠ la carte de lecteur reste BLANCHE même en mode sombre', () {
      // Fonctionnel, pas décoratif : une douchette lit un code-barres sur du
      // blanc. Un thème sombre appliqué ici rendrait la carte inutilisable au
      // comptoir — un défaut qu'aucun test de contraste n'attraperait, puisque
      // blanc sur noir contraste parfaitement.
      for (final t in [gafesoClair(), gafesoSombre()]) {
        expect(t.extension<GafesoPalette>()!.carte, const Color(0xFFFFFFFF));
      }
    });
  });

  group('⚠ AUCUNE couleur littérale hors du fichier de thème', () {
    // Le fichier de thème est le seul endroit autorisé : c'est lui qui DÉFINIT
    // les couleurs. Partout ailleurs, une couleur littérale est une couleur qui
    // ne suivra pas le mode sombre.
    const autorise = 'lib/theme/gafeso_theme.dart';
    final interdits = RegExp(r'Color\(0x|Colors\.[a-zA-Z]');

    test('le garde trouve bien les fichiers (sinon il ne garde rien)', () {
      // ⚠ Un garde qui parcourt zéro fichier passe toujours. On le dit.
      final n = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .length;
      expect(n, greaterThan(20), reason: 'seulement $n fichiers inspectés');
    });

    test('le motif reconnaît bien une faute (témoin positif)', () {
      expect(interdits.hasMatch('color: Colors.black54,'), isTrue);
      expect(interdits.hasMatch('const Color(0xFFE07A2B)'), isTrue);
      expect(interdits.hasMatch('color: context.gafeso.texteSecondaire'), isFalse);
      expect(interdits.hasMatch('ColorScheme.fromSeed'), isFalse);
    });

    test('lib/ est propre', () {
      final fautes = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final chemin = f.path.replaceAll(r'\', '/');
        if (chemin.endsWith(autorise)) continue;
        final lignes = f.readAsLinesSync();
        for (var i = 0; i < lignes.length; i++) {
          final l = lignes[i];
          // On ignore les commentaires : ils citent les couleurs pour expliquer.
          if (l.trimLeft().startsWith('//')) continue;
          if (interdits.hasMatch(l)) fautes.add('$chemin:${i + 1}  ${l.trim()}');
        }
      }
      expect(fautes, isEmpty,
          reason: 'couleur littérale hors du thème :\n${fautes.join('\n')}');
    });
  });
}
