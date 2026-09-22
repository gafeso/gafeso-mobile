import 'dart:convert';
import 'dart:io';

/// Cache disque des couvertures.
///
/// ⚠ POURQUOI UN CACHE, ET PAS `Image.network` TOUT SEUL.
/// Cette app existe pour fonctionner sans réseau. `Image.network` ne garde rien
/// entre deux lancements : une étagère parcourue hier redemanderait chaque
/// vignette aujourd'hui, et n'afficherait rien en 3G ou hors ligne. Une
/// couverture vue une fois doit rester vue.
///
/// ⚠ CE QU'IL NE FAIT PAS, DÉLIBÉRÉMENT : il ne télécharge JAMAIS en rafale et
/// ne bloque jamais un écran. Une couverture absente est un défaut d'agrément,
/// pas une panne — l'écran s'affiche sans elle et elle arrive après, ou jamais.
class CoverCache {
  CoverCache({required this.dossier, HttpClient? client, this.maxFichiers = 200})
      : _client = client ?? HttpClient();

  /// Répertoire privé de l'app. Jamais le stockage externe : une couverture est
  /// anodine, mais le produit n'écrit rien de lisible hors de son bac à sable.
  final Directory dossier;
  final HttpClient _client;

  /// Borne du cache. Un fonds de 480 notices tiendrait 480 vignettes ; on garde
  /// les plus récemment utilisées et on jette le reste.
  final int maxFichiers;

  /// Extensions qu'on sait décoder. ⚠ Le SVG est EXCLU : Flutter ne le rend pas
  /// sans dépendance supplémentaire, et les seules couvertures SVG du produit
  /// sont des fixtures de démonstration. Les couvertures réelles sont extraites
  /// des PDF et déposées en raster.
  static const _extensionsRendables = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};

  Directory get _dir => Directory('${dossier.path}/couvertures');

  /// Résout une `coverUrl` du contrat en URL absolue chargeable, ou `null`.
  ///
  /// Le contrat sert des chemins RELATIFS pour les couvertures de démonstration
  /// (`/demo/couvertures/01.svg`) et des URL absolues pour les couvertures
  /// réelles. Les relatives se résolvent contre l'origine du serveur — celle que
  /// l'usager a saisie ou scannée, pas l'API : ces fichiers sont servis par le
  /// site.
  static Uri? resoudre(String? coverUrl, {String? origine}) {
    final brut = (coverUrl ?? '').trim();
    if (brut.isEmpty) return null;

    Uri? uri;
    if (brut.startsWith('http://') || brut.startsWith('https://')) {
      uri = Uri.tryParse(brut);
    } else if (origine != null && origine.isNotEmpty) {
      uri = Uri.tryParse('${origine.replaceAll(RegExp(r"/+$"), "")}/${brut.replaceAll(RegExp(r"^/+"), "")}');
    }
    if (uri == null || !uri.hasScheme) return null;

    final chemin = uri.path.toLowerCase();
    final point = chemin.lastIndexOf('.');
    if (point < 0) return null;
    if (!_extensionsRendables.contains(chemin.substring(point))) return null;
    return uri;
  }

  File _fichierPour(Uri uri) {
    // Nom stable et sûr : l'URL peut contenir n'importe quoi, le nom de fichier
    // non. Base64url d'une empreinte courte suffit et évite les collisions.
    final cle = base64Url.encode(utf8.encode(uri.toString())).replaceAll('=', '');
    final court = cle.length <= 64 ? cle : cle.substring(cle.length - 64);
    return File('${_dir.path}/$court');
  }

  /// Le fichier local s'il est déjà là, sinon `null` — sans réseau, sans délai.
  File? enCache(Uri uri) {
    final f = _fichierPour(uri);
    return f.existsSync() && f.lengthSync() > 0 ? f : null;
  }

  /// Récupère la couverture : cache d'abord, réseau ensuite.
  /// Renvoie `null` sur tout échec — l'appelant affiche alors son substitut.
  Future<File?> obtenir(Uri uri) async {
    final dejaLa = enCache(uri);
    if (dejaLa != null) return dejaLa;

    try {
      final req = await _client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final octets = await consolidateBytes(res);
      // Une couverture qui pèse plus que ça n'en est pas une : on ne remplit
      // pas l'appareil d'un fichier qu'on n'a pas demandé.
      if (octets.isEmpty || octets.length > 3 * 1024 * 1024) return null;

      await _dir.create(recursive: true);
      final f = _fichierPour(uri);
      await f.writeAsBytes(octets, flush: true);
      _elaguer();
      return f;
    } catch (_) {
      // Réseau coupé, DNS, délai, hôte inconnu : pas d'image, et c'est tout.
      return null;
    }
  }

  static Future<List<int>> consolidateBytes(HttpClientResponse res) async {
    final morceaux = <int>[];
    await for (final m in res) {
      morceaux.addAll(m);
    }
    return morceaux;
  }

  /// Garde les [maxFichiers] plus récemment modifiés. Élagage silencieux : un
  /// échec ici ne doit jamais remonter jusqu'à un écran.
  void _elaguer() {
    try {
      if (!_dir.existsSync()) return;
      final fichiers = _dir.listSync().whereType<File>().toList();
      if (fichiers.length <= maxFichiers) return;
      fichiers.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      for (final f in fichiers.sublist(maxFichiers)) {
        f.deleteSync();
      }
    } catch (_) {
      // sans effet
    }
  }

  /// Purge totale (déconnexion, changement d'école).
  Future<void> vider() async {
    try {
      if (_dir.existsSync()) await _dir.delete(recursive: true);
    } catch (_) {
      // sans effet
    }
  }

  void close() => _client.close(force: true);
}
