import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/session/library_store.dart';
import 'package:gafeso_mobile/session/metadonnees_document.dart';
import 'package:gafeso_mobile/theme/gafeso_theme.dart';
import 'package:gafeso_mobile/widgets/couverture_generee.dart';

/// ⚠ **UN SERVEUR ANTÉRIEUR À rc8 NE SERT NI AUTEUR, NI DOMAINE, NI ANNÉE.**
///
/// La démonstration tourne en backend **rc7**. L'étagère doit y retomber sur le
/// cache de l'appareil — **sans erreur, et sans champ vide affiché**. Pas trois
/// tirets là où elle connaissait l'auteur hier.
void main() {
  LocalDocument local({String? auteur, String? domaine, int? annee}) => LocalDocument(
        docId: 'd1',
        title: 'Une thèse',
        licenseId: 'l1',
        licenseBody: '{}',
        signature: 's',
        licensePublicKey: 'p',
        wrappedCek: 'w',
        blobPath: '/tmp/d1.gafs',
        auteur: auteur,
        domaine: domaine,
        annee: annee,
      );

  ShelfDocument distant({String? auteur, String? domaine, int? annee}) => ShelfDocument(
        docId: 'd1',
        title: 'Une thèse',
        fileFormat: 'PDF',
        auteur: auteur,
        domaine: domaine,
        annee: annee,
      );

  group('⚠ LE CAS DE LA DÉMONSTRATION — serveur rc7, charge muette', () {
    test('l’étagère retombe sur le cache de l’appareil', () {
      // Ce que rend un serveur rc7 : l'entrée existe, elle ne porte rien.
      final m = metadonneesDocument(
        distant: distant(),
        local: local(auteur: 'Ouoba, Justine', domaine: 'arts', annee: 2025),
      );
      expect(m.auteur, 'Ouoba, Justine');
      expect(m.domaine, 'arts');
      expect(m.annee, 2025);
    });

    test('rien nulle part : trois nuls, et AUCUNE valeur inventée', () {
      final m = metadonneesDocument(distant: distant(), local: local());
      expect(m.auteur, isNull);
      expect(m.domaine, isNull);
      expect(m.annee, isNull);
    });

    testWidgets('⚠ et l’écran n’affiche alors AUCUN champ vide', (t) async {
      // Un champ absent disparaît : il ne devient ni tiret, ni « s.d. », ni
      // « Auteur inconnu ». C'est ce qui distingue une couverture sobre d'une
      // couverture cassée.
      await t.pumpWidget(MaterialApp(
        theme: gafesoClair(),
        home: const Scaffold(
          body: Center(
            child: CouvertureGeneree(titre: 'Une thèse', largeur: 160, hauteur: 220),
          ),
        ),
      ));
      await t.pump();
      expect(find.text('Une thèse'), findsOneWidget);
      for (final laid in ['—', '-', 's.d.', 'inconnu', 'null', 'N/A']) {
        expect(find.textContaining(laid), findsNothing, reason: 'affiche « $laid »');
      }
    });
  });

  group('⚠ CONTRÔLE NÉGATIF — un serveur rc8 reprend bien la main', () {
    test('la route parle : c’est ELLE qui est affichée, pas le cache', () {
      // Sans ce cas, « on retombe sur le cache » serait aussi vrai d'un code
      // qui ignorerait purement et simplement la route.
      final m = metadonneesDocument(
        distant: distant(auteur: 'Nouveau, Nom', domaine: 'medecine', annee: 2026),
        local: local(auteur: 'Ancien, Nom', domaine: 'arts', annee: 2001),
      );
      expect(m.auteur, 'Nouveau, Nom', reason: 'le cache a écrasé la route');
      expect(m.domaine, 'medecine');
      expect(m.annee, 2026);
    });

    test('⚠ un domaine CORRIGÉ par le catalogueur atteint bien le lecteur', () {
      // C'est la raison d'être de l'ordre : prendre le local en premier
      // figerait une correction faite depuis.
      final m = metadonneesDocument(
        distant: distant(domaine: 'histoire'),
        local: local(domaine: 'arts'),
      );
      expect(m.domaine, 'histoire');
    });
  });

  group('les cas mêlés, que le « tout ou rien » perdrait', () {
    test('⚠ route PARTIELLE : ce qu’elle ne dit pas vient du cache', () {
      // Un serveur peut servir le domaine et pas l'année. Prendre le distant
      // en bloc perdrait l'année connue localement, pour la seule raison qu'un
      // autre champ manquait.
      final m = metadonneesDocument(
        distant: distant(domaine: 'medecine'),
        local: local(auteur: 'Sanogo, Issa', domaine: 'arts', annee: 2012),
      );
      expect(m.domaine, 'medecine', reason: 'la route prime sur ce qu’elle dit');
      expect(m.auteur, 'Sanogo, Issa', reason: 'le cache comble ce qu’elle tait');
      expect(m.annee, 2012);
    });

    test('document jamais téléchargé et serveur muet : rien, sans planter', () {
      final m = metadonneesDocument(distant: distant(), local: null);
      expect(m.auteur, isNull);
      expect(m.domaine, isNull);
      expect(m.annee, isNull);
    });

    test('hors ligne — aucune entrée distante : le cache seul répond', () {
      final m = metadonneesDocument(
        distant: null,
        local: local(auteur: 'Congo, Pauline', domaine: 'droit', annee: 2012),
      );
      expect(m.auteur, 'Congo, Pauline');
      expect(m.domaine, 'droit');
    });
  });

  group('⚠ la teinte reste STABLE malgré la bascule de source', () {
    test('même domaine, même couleur, qu’il vienne de la route ou du cache', () {
      // Sinon la couverture d'un même document changerait de couleur selon
      // qu'on est en ligne ou non — et la couverture ne servirait plus à rien.
      final enLigne = metadonneesDocument(distant: distant(domaine: 'droit'), local: local());
      final horsLigne = metadonneesDocument(distant: null, local: local(domaine: 'droit'));
      expect(teinteDomaine(enLigne.domaine), teinteDomaine(horsLigne.domaine));
    });
  });
}
