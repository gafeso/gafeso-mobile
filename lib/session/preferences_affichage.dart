import 'package:flutter/services.dart';

/// Comment l'étagère se présente : en grille ou en liste.
///
/// ⚠ MÉMORISÉ, et c'est le point. Un choix d'affichage qu'il faut refaire à
/// chaque ouverture n'est pas un choix, c'est une corvée — et l'usager finit
/// par conclure que le bouton ne marche pas.
///
/// Rangé dans le coffre local comme le reste, mais **à part de la session** :
/// une déconnexion rend l'appareil à quelqu'un d'autre pour ses documents, pas
/// pour sa préférence d'affichage. La purger serait une punition sans objet.
class PreferencesAffichage {
  PreferencesAffichage({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('com.gafeso/secure');

  static const _cle = 'affichage.etagere';
  static const _grille = 'grille';
  static const _liste = 'liste';

  final MethodChannel _ch;

  /// ⚠ LA GRILLE EST LE DÉFAUT. C'est elle qui montre les couvertures, donc ce
  /// que l'étagère a de reconnaissable ; la liste est le repli de qui préfère
  /// la densité. Une valeur illisible retombe sur la grille plutôt que de
  /// lever : une préférence abîmée ne doit pas empêcher d'ouvrir l'écran.
  Future<bool> enGrille() async {
    try {
      final v = await _ch.invokeMethod<String>('get', {'name': _cle});
      return v != _liste;
    } catch (_) {
      return true;
    }
  }

  Future<void> poser({required bool grille}) async {
    try {
      await _ch.invokeMethod('put', {'name': _cle, 'value': grille ? _grille : _liste});
    } catch (_) {
      // Coffre indisponible : l'affichage reste celui de la session en cours.
      // Mieux vaut une préférence non retenue qu'un écran qui refuse de
      // changer de forme.
    }
  }
}
