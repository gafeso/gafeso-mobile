/// Décodage du **code d'école** (slug) : saisie manuelle ou QR présenté au comptoir.
///
/// Formats acceptés (tolérants, car le QR peut être produit par plusieurs outils) :
///   - slug nu :                      `zinda`
///   - URI applicatif :               `gafeso://tenant/zinda`
///   - URL de l'école :               `https://zinda.gafeso.bf` (le sous-domaine est le slug)
///   - URL avec paramètre :           `https://gafeso.bf/app?tenant=zinda`
///
/// La validation reprend la règle du backend (`isValidSlug`) : minuscule initiale, puis
/// minuscules/chiffres/tirets, 2 à 49 caractères. Rien n'est envoyé au réseau ici.
class TenantCode {
  static final RegExp _slug = RegExp(r'^[a-z][a-z0-9-]{1,48}$');

  static bool isValidSlug(String s) => _slug.hasMatch(s);

  /// Extrait un slug valide d'une saisie/charge utile de QR, ou `null` si rien d'exploitable.
  static String? parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    // Cas simple : déjà un slug.
    final lower = raw.toLowerCase();
    if (isValidSlug(lower)) return lower;

    final uri = Uri.tryParse(raw);
    if (uri == null) return null;

    // gafeso://tenant/<slug>
    if (uri.scheme == 'gafeso') {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final candidate = (uri.host.isNotEmpty && uri.host != 'tenant')
          ? uri.host
          : (segs.isNotEmpty ? segs.last : '');
      final c = candidate.toLowerCase();
      if (isValidSlug(c)) return c;
    }

    // ?tenant=<slug> (prioritaire sur l'hôte : intention explicite)
    final q = uri.queryParameters['tenant']?.toLowerCase();
    if (q != null && isValidSlug(q)) return q;

    // https://<domaine>/e/<slug> — FORME OFFICIELLE du QR d'établissement.
    //
    // Placée AVANT la règle du sous-domaine : un chemin `/e/<slug>` est une
    // intention explicite, là où le premier label de l'hôte n'est qu'une
    // heuristique. Sur `https://zinda.gafeso.bf/e/droit-l1`, c'est `droit-l1`
    // qui a été imprimé sur l'affiche, pas `zinda`.
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length >= 2 && segs[segs.length - 2].toLowerCase() == 'e') {
      final c = segs.last.toLowerCase();
      if (isValidSlug(c)) return c;
    }

    // https://<slug>.domaine.tld → premier label de l'hôte
    if (uri.host.isNotEmpty) {
      final labels = uri.host.toLowerCase().split('.');
      if (labels.length >= 3 && isValidSlug(labels.first)) return labels.first;
    }

    return null;
  }

  /// Origine à interroger pour le descripteur `/.well-known/gafeso.json`.
  ///
  /// Le QR ne porte PAS l'adresse de l'API : une affiche imprimée est un objet
  /// physique qui survit à la configuration, et graver l'API dedans
  /// condamnerait tout le papier du bâtiment le jour d'une migration de
  /// serveur. On rend donc l'origine SCANNÉE, où l'application ira lire
  /// l'adresse réelle.
  ///
  /// `null` pour un slug nu ou un `gafeso://` : ces formes ne portent aucune
  /// origine. Elles restent parfaitement valides quand un serveur est DÉJÀ
  /// configuré — c'est le cas du lecteur qui change d'école sans changer
  /// d'installation.
  static Uri? origin(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
  }

  /// URL du descripteur pour une origine donnée.
  static Uri descriptorUrl(Uri origin) => origin.replace(path: '/.well-known/gafeso.json');
}
