import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/session/preferences_affichage.dart';

/// ⚠ **LA FORME DE L'ÉTAGÈRE SE CHOISIT UNE FOIS.**
///
/// Un réglage qu'il faut refaire à chaque ouverture n'est pas un choix, c'est
/// une corvée — et l'usager finit par conclure que le bouton ne marche pas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> coffre;
  late int lectures;

  PreferencesAffichage prefs({bool coffrePanne = false}) {
    const canal = MethodChannel('com.gafeso/secure');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, (c) async {
      if (coffrePanne) throw PlatformException(code: 'KEYSTORE');
      final nom = (c.arguments as Map?)?['name'] as String?;
      if (c.method == 'get') {
        lectures++;
        return coffre[nom];
      }
      if (c.method == 'put') coffre[nom!] = (c.arguments as Map)['value'] as String;
      return null;
    });
    return PreferencesAffichage(channel: canal);
  }

  setUp(() {
    coffre = {};
    lectures = 0;
  });

  test('⚠ la GRILLE est le défaut — c’est elle qui montre les couvertures', () {
    // La liste est le repli de qui préfère la densité ; la grille est ce que
    // l'étagère a de reconnaissable.
    expect(prefs().enGrille(), completion(isTrue));
  });

  test('le choix de la liste est retenu', () async {
    final p = prefs();
    await p.poser(grille: false);
    expect(await p.enGrille(), isFalse);
    expect(coffre['affichage.etagere'], 'liste');
  });

  test('le retour à la grille est retenu aussi', () async {
    final p = prefs();
    await p.poser(grille: false);
    await p.poser(grille: true);
    expect(await p.enGrille(), isTrue);
  });

  test('⚠ une valeur ABÎMÉE retombe sur la grille, elle ne lève pas', () async {
    // Une préférence corrompue ne doit pas empêcher d'ouvrir l'écran.
    coffre['affichage.etagere'] = 'n’importe quoi';
    expect(await prefs().enGrille(), isTrue);
  });

  test('⚠ coffre EN PANNE : on affiche quand même, en grille', () async {
    final p = prefs(coffrePanne: true);
    expect(await p.enGrille(), isTrue);
    // Et poser une préférence ne lève pas non plus : mieux vaut un choix non
    // retenu qu'un écran qui refuse de changer de forme.
    await p.poser(grille: false);
  });

  test('⚠ TÉMOIN — le coffre est bien interrogé', () async {
    // Sans ce cas, « la grille est le défaut » serait aussi vrai d'un code qui
    // ne lirait jamais la préférence.
    await prefs().enGrille();
    expect(lectures, 1);
  });
}
