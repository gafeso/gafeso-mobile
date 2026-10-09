import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/screens/record_screen.dart';

/// Fiche notice — point de jonction entre la recherche et la lecture hors ligne.
void main() {
  late bool horsLigne;
  late String noticeJson;
  late List<String> reservations;
  late RenewResult reponseReservation;

  // Structure relevée sur GET /opac/records/:id en fonctionnement.
  String notice({
    List<Map<String, dynamic>> items = const [],
    bool digital = false,
    String fileFormat = 'PDF',
    String? embargoUntil,
    Map<String, dynamic>? provenance,
    String? recordType,
    String? titleComplement,
    String? isbn,
    String? language,
    String? publicationCity,
    String? defenseUniversity,
    String? defensePlace,
    List<Map<String, dynamic>>? contributors,
    List<String>? keywords,
    Map<String, dynamic>? availability,
  }) =>
      jsonEncode({
        'id': 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
        'title': 'Droit constitutionnel burkinabè',
        'author': 'Traoré, Awa',
        'summary': 'Un précis de droit constitutionnel.',
        'publisher': 'Presses universitaires',
        'publishYear': 2023,
        'category': 'droit',
        'items': items,
        // ⚠ La clé servie par l'OPAC est `fileFormat`. Le fixture disait
        // `format` : sans effet tant que l'écran ne lisait qu'un booléen,
        // faux dès qu'il lit le format.
        'digitalCopy': digital ? {'id': 'd1', 'fileFormat': fileFormat} : null,
        'embargoUntil': embargoUntil,
        // 28ᵉ clé du contrat, servie à TOUS (membre ou non) — P7-3.
        'provenance': provenance,
        'recordType': recordType,
        'titleComplement': titleComplement,
        'isbn': isbn,
        'language': language,
        'publicationCity': publicationCity,
        'defenseUniversity': defenseUniversity,
        'defensePlace': defensePlace,
        'contributors': contributors,
        'keywords': keywords,
        'availability': availability,
      });

  Map<String, dynamic> exemplaire(String statut) => {
        'barcode': 'BIB-000123',
        'status': statut,
        'location': 'Salle de lecture',
        'callNumber': '342.5 TRA',
      };

  setUp(() {
    horsLigne = false;
    reservations = [];
    reponseReservation = RenewResult(ok: true);
    noticeJson = notice(items: [exemplaire('AVAILABLE')]);
  });

  /// Monte la fiche avec ou sans circulation physique.
  Future<void> monterAvec(WidgetTester tester, {required bool circulation}) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        recordId: 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
        titleHint: 'Droit constitutionnel burkinabè',
        circulation: circulation,
        fetchRecord: (id) async => jsonDecode(noticeJson) as Object,
        placeHold: (id) async => RenewResult(ok: true),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> monter(WidgetTester tester, {bool estLocal = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        recordId: 'bdefba53-70ee-4214-b83f-a4cc7f6bde75',
        titleHint: 'Droit constitutionnel burkinabè',
        estLocal: estLocal,
        fetchRecord: (id) async {
          if (horsLigne) throw const SocketException('réseau coupé');
          return jsonDecode(noticeJson) as Object;
        },
        placeHold: (id) async {
          reservations.add(id);
          return reponseReservation;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche les métadonnées et l’état des exemplaires', (tester) async {
    await monter(tester);
    expect(find.text('Traoré, Awa'), findsOneWidget);
    expect(find.text('Presses universitaires · 2023 · droit'), findsOneWidget);
    // « AVAILABLE » ne dit rien à un étudiant.
    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('Rayon Salle de lecture · Cote 342.5 TRA'), findsOneWidget);
  });

  testWidgets('DISPONIBLE : on n’offre pas de réserver', (tester) async {
    // Envoyer attendre quelqu'un qui peut emprunter tout de suite serait absurde.
    await monter(tester);
    expect(find.text('Disponible au comptoir'), findsOneWidget);
    expect(find.text('Réserver'), findsNothing);
  });

  testWidgets('TOUT EN PRÊT : on propose de réserver', (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')]);
    await monter(tester);
    expect(find.text('En prêt'), findsOneWidget);
    expect(find.text('Réserver'), findsOneWidget);

    await tester.tap(find.text('Réserver'));
    await tester.pumpAndSettle();
    expect(reservations.single, 'bdefba53-70ee-4214-b83f-a4cc7f6bde75');
  });

  testWidgets('refus de réservation : le MOTIF du serveur est affiché', (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')]);
    reponseReservation = RenewResult(ok: false, reason: 'Vous avez déjà réservé ce document.');
    await monter(tester);

    await tester.tap(find.text('Réserver'));
    await tester.pumpAndSettle();

    expect(find.text('Vous avez déjà réservé ce document.'), findsOneWidget,
        reason: '« échec » ne dirait pas à l’usager quoi faire');
  });

  testWidgets('sans exemplaire physique : ni réservation, ni faux espoir', (tester) async {
    noticeJson = notice(items: const []);
    await monter(tester);
    expect(find.textContaining('Aucun exemplaire physique'), findsOneWidget);
    expect(find.text('Réserver'), findsNothing);
    expect(find.text('Disponible au comptoir'), findsNothing);
  });

  testWidgets('document numérique : le lien vers la lecture hors ligne apparaît',
      (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')], digital: true);
    await monter(tester);
    // ⚠ Le libellé dit ce qui va se passer. « Télécharger » parce que le
    // document n'est pas sur l'appareil ; il dirait « Lire hors ligne » s'il
    // l'était. « Ouvrir » couvrirait les deux et n'informerait sur aucun — et
    // sur une connexion comptée, savoir si un geste va coûter des mégaoctets
    // n'est pas un détail.
    expect(find.widgetWithText(FilledButton, 'Télécharger'), findsOneWidget);
    expect(find.text('Lire hors ligne'), findsNothing);
  });

  testWidgets('⚠ document DÉJÀ sur l’appareil : le bouton dit « Lire hors ligne »',
      (tester) async {
    noticeJson = notice(items: [exemplaire('CHECKED_OUT')], digital: true);
    await monter(tester, estLocal: true);
    expect(find.widgetWithText(FilledButton, 'Lire hors ligne'), findsOneWidget);
    expect(find.text('Télécharger'), findsNothing);
  });

  testWidgets('un statut INCONNU est affiché tel quel, jamais réinterprété',
      (tester) async {
    // Traduire un code inconnu en « indisponible » inventerait une
    // signification ; montrer le code laisse au moins une piste.
    noticeJson = notice(items: [exemplaire('EN_RELIURE')]);
    await monter(tester);
    expect(find.text('EN_RELIURE'), findsOneWidget);
  });

  testWidgets('HORS LIGNE : on l’annonce, on ne prétend pas que la notice n’existe pas',
      (tester) async {
    horsLigne = true;
    await monter(tester);
    expect(find.text('Fiche indisponible hors connexion'), findsOneWidget);
    expect(find.textContaining('étagère'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  testWidgets('le titre connu s’affiche AVANT la réponse du serveur', (tester) async {
    // Une barre de progression anonyme laisse douter d'avoir ouvert la bonne
    // notice. Le titre vient de la liste de résultats, il est déjà connu.
    await tester.pumpWidget(MaterialApp(
      home: RecordScreen(
        recordId: 'r1',
        titleHint: 'Droit constitutionnel burkinabè',
        fetchRecord: (id) => Future.delayed(const Duration(seconds: 5), () => <String, dynamic>{}),
        placeHold: (id) async => RenewResult(ok: true),
      ),
    ));
    await tester.pump();
    expect(find.text('Droit constitutionnel burkinabè'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Laisse la minuterie s'achever proprement.
    await tester.pump(const Duration(seconds: 6));
  });

  group('carte du document numérique — elle ne promet que le vrai', () {
    testWidgets('PDF hors embargo : la lecture hors connexion est annoncée',
        (tester) async {
      noticeJson = notice(digital: true, fileFormat: 'PDF');
      await monter(tester);

      // Le geste principal est un BOUTON, et son libellé dit ce qui va se
      // passer : « Télécharger » quand le document n'est pas encore là.
      expect(find.widgetWithText(FilledButton, 'Télécharger'), findsOneWidget);
    });

    testWidgets('EPUB : jamais de promesse de lecture hors connexion',
        (tester) async {
      // `myDocuments` ne descend que le PDF : promettre le hors-ligne pour un
      // EPUB envoie le lecteur vers un refus.
      noticeJson = notice(digital: true, fileFormat: 'EPUB');
      await monter(tester);

      expect(find.textContaining('hors connexion'), findsOneWidget);
      expect(find.text('Télécharger'), findsNothing);
      expect(find.text('Document numérique disponible (EPUB)'), findsOneWidget);
      expect(find.textContaining('que le PDF'), findsOneWidget);
    });

    testWidgets('sous embargo : la date est donnée, rien n’est promis',
        (tester) async {
      final dans2ans = DateTime.now().add(const Duration(days: 730));
      noticeJson = notice(
        digital: true,
        fileFormat: 'PDF',
        embargoUntil: dans2ans.toUtc().toIso8601String(),
      );
      await monter(tester);

      expect(find.text('Document sous embargo'), findsOneWidget);
      expect(find.text('Télécharger'), findsNothing);
      final l = dans2ans.toLocal();
      final jour = '${l.day.toString().padLeft(2, '0')}/'
          '${l.month.toString().padLeft(2, '0')}/${l.year}';
      expect(find.textContaining(jour), findsOneWidget);
    });

    testWidgets('embargo EXPIRÉ : le PDF redevient téléchargeable',
        (tester) async {
      noticeJson = notice(
        digital: true,
        fileFormat: 'PDF',
        embargoUntil:
            DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
      );
      await monter(tester);

      expect(find.text('Document sous embargo'), findsNothing);
      expect(find.text('Télécharger'), findsOneWidget);
    });

    testWidgets('aucun document numérique : aucune carte', (tester) async {
      noticeJson = notice(digital: false);
      await monter(tester);

      expect(find.textContaining('Document numérique'), findsNothing);
      expect(find.text('Document sous embargo'), findsNothing);
    });
  });


  group('provenance — l’invariant P7-3 tient aussi côté client', () {
    testWidgets('notice moissonnée : elle est marquée comme telle', (tester) async {
      noticeJson = notice(provenance: {
        'source': {'id': 's1', 'name': 'Université d’Amani'},
        'oaiIdentifier': 'oai:amani.bf:1234',
        'lien': 'https://depot.amani.bf/notice/1234',
      });
      await monter(tester);

      expect(
        find.text('Notice moissonnée — Université d’Amani'),
        findsOneWidget,
      );
      expect(find.textContaining('n’a pas été catalogée ici'), findsOneWidget);
      expect(find.text('https://depot.amani.bf/notice/1234'), findsOneWidget);
    });

    testWidgets('notice locale : aucun bandeau', (tester) async {
      noticeJson = notice(); // provenance absente → null
      await monter(tester);

      expect(find.textContaining('Notice moissonnée'), findsNothing);
    });

    testWidgets('source sans lien : on marque, on n’invente pas de lien',
        (tester) async {
      noticeJson = notice(provenance: {
        'source': {'id': 's2', 'name': 'Université d’Exemple'},
        'oaiIdentifier': 'oai:exemple.bf:77',
        'lien': null,
      });
      await monter(tester);

      expect(find.text('Notice moissonnée — Université d’Exemple'), findsOneWidget);
      expect(find.textContaining('http'), findsNothing);
    });
  });


  group('la fiche montre ce qu’un dépôt de thèses a de spécifique', () {
    testWidgets('thèse : direction, soutenance et type sont affichés',
        (tester) async {
      // 211 des 480 notices mesurées portent un DIRECTEUR_MEMOIRE et une
      // université de soutenance. L’app n’en montrait rien.
      noticeJson = notice(
        recordType: 'these',
        defenseUniversity: 'Université de Tamaro',
        defensePlace: 'Tamaro',
        contributors: [
          {'name': 'Sirima, Rasmata', 'role': 'AUTEUR_PRINCIPAL'},
          {'name': 'Sanou, Alain', 'role': 'DIRECTEUR_MEMOIRE'},
        ],
      );
      await monter(tester);

      expect(find.text('Sirima, Rasmata'), findsOneWidget);
      expect(find.text('Sanou, Alain'), findsOneWidget);
      expect(find.text('Direction'), findsOneWidget);
      expect(find.text('Thèse'), findsWidgets);
      expect(find.textContaining('Thèse soutenu'), findsOneWidget);
      expect(find.textContaining('Université de Tamaro'), findsOneWidget);
    });

    testWidgets('⚠ un rôle technique n’est jamais montré tel quel',
        (tester) async {
      noticeJson = notice(contributors: [
        {'name': 'Diallo, Boureima', 'role': 'DIRECTEUR_MEMOIRE'},
      ]);
      await monter(tester);

      expect(find.textContaining('DIRECTEUR_MEMOIRE'), findsNothing);
      expect(find.text('Direction'), findsOneWidget);
    });

    testWidgets('ouvrage : pas de bloc de soutenance', (tester) async {
      // Un ouvrage ne se soutient pas ; le bloc n’a rien à dire.
      noticeJson = notice(
        recordType: 'ouvrage',
        defenseUniversity: 'Université de Tamaro',
      );
      await monter(tester);

      expect(find.text('Ouvrage'), findsOneWidget);
      expect(find.textContaining('soutenu'), findsNothing);
    });

    testWidgets('sous-titre, mots-clés et ISBN sont affichés', (tester) async {
      noticeJson = notice(
        titleComplement: 'le cas du Burkina Faso',
        keywords: ['droit constitutionnel', 'Afrique de l’Ouest'],
        isbn: '978-2-1234-5680-3',
      );
      await monter(tester);

      expect(find.text('le cas du Burkina Faso'), findsOneWidget);
      expect(find.text('droit constitutionnel'), findsOneWidget);
      expect(find.text('Afrique de l’Ouest'), findsOneWidget);
      expect(find.text('978-2-1234-5680-3'), findsOneWidget);
    });

    // ⚠ Deux tests et non un : `monter` deux fois dans le MÊME test réutilise
    // l'état de l'écran — la notice n'est chargée qu'à l'initState, et la
    // seconde assertion porterait sur l'affichage de la première.
    testWidgets('⚠ la langue française n’encombre pas les fiches',
        (tester) async {
      // Les 480 notices mesurées sont en `fr` : l’afficher partout ajoute une
      // ligne à chaque fiche sans jamais rien distinguer.
      noticeJson = notice(language: 'fr');
      await monter(tester);
      expect(find.text('Langue'), findsNothing);
    });

    testWidgets('une autre langue, elle, est affichée', (tester) async {
      noticeJson = notice(language: 'en');
      await monter(tester);
      expect(find.text('Langue'), findsOneWidget);
      expect(find.text('en'), findsOneWidget);
    });

    testWidgets('sans contributeurs servis, l’auteur reste affiché',
        (tester) async {
      // Repli : une réponse ancienne ne doit pas montrer MOINS qu’avant.
      noticeJson = notice();
      await monter(tester);
      expect(find.text('Traoré, Awa'), findsOneWidget);
    });

    testWidgets('⚠ la disponibilité du SERVEUR prime sur le calcul local',
        (tester) async {
      // Deux exemplaires en prêt, mais le serveur en annonce un de libre :
      // c’est lui qui tranche, pas notre arithmétique sur `items`.
      noticeJson = notice(
        items: [exemplaire('CHECKED_OUT'), exemplaire('CHECKED_OUT')],
        availability: {'totalItems': 2, 'available': 1, 'borrowable': true},
      );
      await monter(tester);

      expect(find.text('Disponible au comptoir'), findsOneWidget);
    });
  });


  group('⚠ bibliothèque NUMÉRIQUE — rien ne promet un comptoir', () {
    testWidgets('sans circulation : ni exemplaires, ni réservation',
        (tester) async {
      // Une université virtuelle n'a ni comptoir ni exemplaire. « Aucun
      // exemplaire physique » y serait exact et inutile, et « Réserver »
      // promettrait une file d'attente qui n'existe pas.
      noticeJson = notice(items: [exemplaire('CHECKED_OUT')]);
      await monterAvec(tester, circulation: false);

      expect(find.text('Exemplaires'), findsNothing);
      expect(find.textContaining('exemplaire physique'), findsNothing);
      expect(find.text('Réserver'), findsNothing);
      expect(find.text('Disponible au comptoir'), findsNothing);
    });

    testWidgets('⚠ mais les MÉTADONNÉES restent entières', (tester) async {
      // On retire une promesse de service, pas le contenu du catalogue.
      noticeJson = notice(
        recordType: 'these',
        defenseUniversity: 'Université de Tamaro',
        keywords: ['droit constitutionnel'],
      );
      await monterAvec(tester, circulation: false);

      // Le titre paraît deux fois : barre de l'écran et corps de la fiche.
      expect(find.text('Droit constitutionnel burkinabè'), findsWidgets);
      expect(find.textContaining('Université de Tamaro'), findsOneWidget);
      expect(find.text('droit constitutionnel'), findsOneWidget);
    });

    testWidgets('avec circulation : tout reste affiché', (tester) async {
      noticeJson = notice(items: [exemplaire('AVAILABLE')]);
      await monterAvec(tester, circulation: true);

      expect(find.text('Exemplaires'), findsOneWidget);
      expect(find.text('Disponible au comptoir'), findsOneWidget);
    });

    testWidgets('⚠ par DÉFAUT on montre tout — l’incertitude n’ampute pas',
        (tester) async {
      // Tant que l'état des modules est inconnu, cacher serait pire : l'usager
      // ne saurait pas qu'il manque quelque chose et ne pourrait pas le demander.
      noticeJson = notice(items: [exemplaire('AVAILABLE')]);
      await monter(tester); // sans passer `circulation`
      expect(find.text('Exemplaires'), findsOneWidget);
    });
  });

}
