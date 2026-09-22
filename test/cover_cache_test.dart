import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/cache/cover_cache.dart';

/// Cache des couvertures — ce qui le rend acceptable dans une app hors ligne.
void main() {
  late Directory tmp;
  late HttpServer serveur;
  late int appels;
  late int statut;
  late List<int> corps;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gafeso-cov-');
    appels = 0;
    statut = 200;
    // PNG minimal (en-tête suffisant : le cache ne décode pas, il stocke).
    corps = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3];
    serveur = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serveur.listen((req) async {
      appels++;
      req.response
        ..statusCode = statut
        ..headers.contentType = ContentType('image', 'png')
        ..add(corps);
      await req.response.close();
    });
  });

  tearDown(() async {
    await serveur.close(force: true);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  CoverCache cache({int max = 200}) => CoverCache(dossier: tmp, maxFichiers: max);
  Uri url(String chemin) => Uri.parse('http://127.0.0.1:${serveur.port}$chemin');

  group('résolution des URL', () {
    test('une URL absolue passe', () {
      expect(CoverCache.resoudre('https://s.exemple.bf/covers/a.png')?.path, '/covers/a.png');
    });

    test('un chemin relatif se résout contre l’origine du SITE', () {
      // Le contrat sert `/demo/couvertures/01.png` : ces fichiers sont servis
      // par le site, pas par l'API.
      final u = CoverCache.resoudre('/demo/couvertures/01.png',
          origine: 'https://tamaro.exemple.bf/');
      expect(u.toString(), 'https://tamaro.exemple.bf/demo/couvertures/01.png');
    });

    test('un relatif SANS origine connue est refusé', () {
      expect(CoverCache.resoudre('/demo/couvertures/01.png'), isNull);
    });

    test('⚠ le SVG est refusé — Flutter ne le rend pas sans dépendance', () {
      expect(CoverCache.resoudre('https://s.exemple.bf/c/01.svg'), isNull);
      expect(
        CoverCache.resoudre('/demo/couvertures/01.svg', origine: 'https://x.bf'),
        isNull,
      );
    });

    test('vide, nul, sans extension : refusés', () {
      expect(CoverCache.resoudre(null), isNull);
      expect(CoverCache.resoudre('   '), isNull);
      expect(CoverCache.resoudre('https://x.bf/sans-extension'), isNull);
    });
  });

  group('cache disque', () {
    test('⚠ la deuxième demande ne touche PAS le réseau', () async {
      final c = cache();
      final a = await c.obtenir(url('/a.png'));
      expect(a, isNotNull);
      expect(appels, 1);

      final b = await c.obtenir(url('/a.png'));
      expect(b!.path, a!.path);
      expect(appels, 1, reason: 'servi depuis le disque');
      c.close();
    });

    test('⚠ une couverture vue survit à un REDÉMARRAGE de l’app', () async {
      // C'est tout l'intérêt : `Image.network` ne garde rien entre deux
      // lancements, et l'app existe pour marcher sans réseau.
      final c1 = cache();
      await c1.obtenir(url('/b.png'));
      c1.close();

      final c2 = cache(); // instance neuve = nouveau lancement
      expect(c2.enCache(url('/b.png')), isNotNull);
      expect(appels, 1);
      c2.close();
    });

    test('un échec réseau ne lève pas : il rend null', () async {
      final c = cache();
      final mort = Uri.parse('http://127.0.0.1:1/x.png');
      expect(await c.obtenir(mort), isNull);
      c.close();
    });

    test('un 404 ne met rien en cache', () async {
      statut = 404;
      final c = cache();
      expect(await c.obtenir(url('/c.png')), isNull);
      expect(c.enCache(url('/c.png')), isNull);
      c.close();
    });

    test('⚠ le cache est BORNÉ — on ne remplit pas l’appareil', () async {
      final c = cache(max: 3);
      for (var i = 0; i < 6; i++) {
        await c.obtenir(url('/n$i.png'));
      }
      final restants = Directory('${tmp.path}/couvertures').listSync().length;
      expect(restants, lessThanOrEqualTo(3));
      c.close();
    });

    test('vider() purge tout (déconnexion, changement d’école)', () async {
      final c = cache();
      await c.obtenir(url('/d.png'));
      await c.vider();
      expect(c.enCache(url('/d.png')), isNull);
      c.close();
    });
  });
}
