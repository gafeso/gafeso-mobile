import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/screens/reader_screen.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';

/// ⚠ **LE FOND DU LECTEUR EST ÉCRIT DEUX FOIS, EN DART ET EN KOTLIN.**
///
/// La page est peinte par la vue native ; ce qui l'entoure est peint par
/// Flutter. Les deux doivent s'accorder au bit près, sinon le mode Nuit laisse
/// une bande claire sous la page — un défaut qui ne casse rien et que personne
/// ne signale.
///
/// Kotlin ne lit pas Dart : la duplication est inévitable. Ce qui ne l'est pas,
/// c'est qu'elle dérive. Ce test LIT LE FICHIER KOTLIN et compare.
void main() {
  final kotlin = File('android/app/src/main/kotlin/com/gafeso/reader/ModeLecture.kt');

  /// Les `Color.parseColor("#…")` du fichier natif, dans l'ordre des modes.
  Map<String, String> fondsNatifs() {
    final src = kotlin.readAsStringSync();
    final bloc = RegExp(r'val fond: Int[\s\S]*?\}').firstMatch(src)?.group(0) ?? '';
    final out = <String, String>{};
    for (final m in RegExp(r'(CLASSIQUE|SEPIA|NUIT)\s*->\s*Color\.parseColor\("(#[0-9A-Fa-f]{6})"\)')
        .allMatches(bloc)) {
      out[m.group(1)!.toLowerCase()] = m.group(2)!.toUpperCase();
    }
    return out;
  }

  test('⚠ le garde trouve bien le fichier natif — sinon il ne garde rien', () {
    expect(kotlin.existsSync(), isTrue, reason: 'ModeLecture.kt introuvable');
    expect(fondsNatifs().length, 3,
        reason: 'trois modes attendus, ${fondsNatifs().length} lus : le motif ne '
            'reconnaît plus le fichier, et ce test ne compare donc plus rien');
  });

  test('les trois fonds Dart valent les trois fonds Kotlin', () {
    final natifs = fondsNatifs();
    for (final m in ModeLecture.values) {
      final dart = fondsModesLecture[m.cle]!;
      final hex = '#${(dart.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      expect(hex, natifs[m.cle], reason: 'mode ${m.cle} : Dart $hex, Kotlin ${natifs[m.cle]}');
    }
  });

  test('⚠ TÉMOIN — le comparateur sait voir un écart', () {
    // Sans ce cas, une erreur de conversion rendrait toutes les comparaisons
    // égales et le test applaudirait une dérive.
    const faux = Color(0xFF123456);
    final hex = '#${(faux.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    expect(hex, '#123456');
    expect(hex, isNot(fondsNatifs()['nuit']));
  });

  group('ce que les modes N’OFFRENT PAS', () {
    test('trois modes, et aucun réglage de police ni d’interligne', () {
      // Un PDF est une page déjà composée : un curseur de taille de texte n'y
      // changerait rien. Afficher un réglage sans effet est pire que ne rien
      // offrir — l'usager essaie, rien ne bouge, il conclut que c'est cassé.
      expect(ModeLecture.values.map((m) => m.cle), ['classique', 'sepia', 'nuit']);
      final src = File('lib/screens/reader_screen.dart').readAsStringSync();
      for (final interdit in ['fontSize:', 'interligne', 'lineHeight', 'police']) {
        // (hors commentaires : on ne cherche que dans le code)
        final lignes = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .where((l) => l.contains(interdit));
        // `fontSize` est admis pour la barre de progression elle-même ; ce qui
        // est interdit, c'est un RÉGLAGE offert à l'usager.
        expect(lignes.where((l) => l.contains('Slider') || l.contains('onChanged')), isEmpty,
            reason: 'un réglage « $interdit » est offert alors qu’il n’a aucun effet');
      }
    });
  });
}
