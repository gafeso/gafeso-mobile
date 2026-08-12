import 'dart:convert';
import 'dart:io';

/// Client HTTP du backend `offline-licensing` (Étape 2).
///
/// Contrat réel prouvé par l'e2e backend :
///   - `POST /offline/devices`            {publicKey (EC P-256 SPKI DER b64), label, platform}
///   - `POST /offline/licenses`           {docId, deviceId} → licence signée Ed25519 + wrappedCek
///   - `GET  /offline/licenses/:id/status`               → active | revoked | expired
///   - `GET  /offline/my-documents`                      → étagère de l'usager
///
/// Le tenant est transmis par l'en-tête **`X-Tenant`** (le middleware backend le résout, avec
/// vérification de cohérence contre le claim du JWT). Aucune clé privée ne transite : seule la
/// clé PUBLIQUE de l'appareil sort du keystore.
class GafesoApi {
  GafesoApi({required this.baseUrl, required this.tenantSlug, this.token, HttpClient? client})
      : _client = client ?? HttpClient();

  final String baseUrl;
  final String tenantSlug;
  String? token;
  final HttpClient _client;

  void close() => _client.close(force: true);

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'X-Tenant': tenantSlug,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final req = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    _headers().forEach(req.headers.set);
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw GafesoApiException(res.statusCode, text, path);
    }
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      // Le serveur a répondu autre chose que du JSON — typiquement une page
      // HTML. La cause de loin la plus fréquente : l'URL pointe vers le SITE
      // et non vers l'API. Sans ce garde, l'écran affichait l'exception brute
      // (« FormatException: Unexpected character (at character 1) »), qui
      // n'apprend rien à l'informaticien qui installe.
      throw GafesoApiException(
        res.statusCode,
        'Le serveur a répondu autre chose que du JSON.\n'
        'Vérifiez que l’adresse configurée pointe vers l’API (elle finit '
        'généralement par « /api »), et non vers le site web.',
        path,
      );
    }
  }

  /// Connexion (email + mot de passe) dans l'école courante (`X-Tenant`). Renvoie le jeton et
  /// l'identité. Le **refresh est reporté** (cf. brief backend) : à l'expiration, on redemande
  /// les identifiants.
  ///
  /// Le backend peut répondre par une étape intermédiaire (2FA active, ou enrôlement 2FA
  /// obligatoire) : on la remonte telle quelle plutôt que d'échouer obscurément — l'UI affiche
  /// alors un message clair. Le second facteur mobile est hors périmètre du MVP.
  Future<LoginResult> login({required String email, required String password}) async {
    final res = await _send('POST', '/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;

    if (res['twoFactorRequired'] == true) {
      return LoginResult.twoFactorRequired();
    }
    if (res['mustEnroll2fa'] == true) {
      return LoginResult.mustEnroll2fa();
    }
    final user = (res['user'] as Map).cast<String, dynamic>();
    token = res['accessToken'] as String;
    return LoginResult.success(
      accessToken: token!,
      userId: user['id'] as String,
      email: user['email'] as String?,
      firstName: user['firstName'] as String?,
      lastName: user['lastName'] as String?,
      role: user['role'] as String?,
    );
  }

  /// Enregistre l'appareil et renvoie l'identifiant attribué par le SERVEUR (à persister :
  /// c'est lui que le backend lie à la licence et utilise en AAD de l'enveloppe EC-KEM).
  Future<String> registerDevice({
    required String publicKeySpkiB64,
    String? label,
    String platform = 'android',
  }) async {
    final res = await _send('POST', '/offline/devices', body: {
      'publicKey': publicKeySpkiB64,
      'label': ?label,
      'platform': platform,
    }) as Map<String, dynamic>;
    return res['id'] as String;
  }

  /// Émet une licence hors-ligne pour un document. Le droit est vérifié côté serveur : un
  /// utilisateur sans accès reçoit un 403 (aucune CEK n'est produite).
  Future<OfflineLicense> issueLicense({required String docId, required String deviceId}) async {
    final res = await _send('POST', '/offline/licenses', body: {
      'docId': docId,
      'deviceId': deviceId,
    }) as Map<String, dynamic>;
    return OfflineLicense.fromJson(res);
  }

  /// Statut d'une licence : le serveur rejoue le droit réel (accès perdu → `revoked`).
  Future<String> licenseStatus(String licenseId) async {
    final res = await _send('GET', '/offline/licenses/$licenseId/status') as Map<String, dynamic>;
    return res['status'] as String;
  }

  /// URL signée (temporaire) du blob CHIFFRÉ. Le backend contrôle que la licence est active
  /// et appartient à l'appelant avant de la délivrer.
  Future<BlobLocation> blobUrl(String licenseId) async {
    final res = await _send('GET', '/offline/licenses/$licenseId/blob-url')
        as Map<String, dynamic>;
    return BlobLocation(
      url: res['url'] as String,
      encSegSize: res['encSegSize'] as int?,
      encAlgo: res['encAlgo'] as String?,
    );
  }

  /// Statut en lot (une seule requête à la reconnexion).
  Future<Map<String, String>> entitlements(List<String> licenseIds) async {
    final res = await _send('POST', '/offline/entitlements', body: {'licenseIds': licenseIds })
        as List<dynamic>;
    return {
      for (final e in res.cast<Map<String, dynamic>>()) e['id'] as String: e['status'] as String,
    };
  }

  /// Documents que l'usager peut lire hors-ligne (« mon étagère »).
  Future<List<ShelfDocument>> myDocuments() async {
    final res = await _send('GET', '/offline/my-documents') as List<dynamic>;
    return res.cast<Map<String, dynamic>>().map(ShelfDocument.fromJson).toList();
  }

  /// Télécharge le blob chiffré (jamais déchiffré ici : écrit tel quel sur disque privé).
  // ── Espace lecteur ──────────────────────────────────────────────────────

  /// Prêts en cours (formes vérifiées sur l'API réelle — voir models/reader_space.dart).
  Future<Object> readerLoans() async => (await _send('GET', '/reader/loans')) as Object;

  Future<Object> readerHolds() async => (await _send('GET', '/reader/holds')) as Object;

  /// Carte de lecteur. Le serveur la CRÉE si le compte n'en a pas encore —
  /// même point de création que la réservation, jamais un second chemin.
  Future<Object> readerCard() async => (await _send('GET', '/reader/card')) as Object;

  /// Renouvelle un prêt. Un refus n'est PAS une panne : on le rend comme un
  /// résultat porteur de motif, pas comme une exception. Une exception aurait
  /// affiché « erreur » là où l'API explique précisément quoi faire.
  Future<RenewResult> renewLoan(String checkoutId) async {
    try {
      final r = await _send('POST', '/reader/loans/$checkoutId/renew');
      final j = (r as Map?) ?? const {};
      return RenewResult(
        ok: true,
        dueDate: j['dueDate'] == null ? null : DateTime.tryParse(j['dueDate'] as String),
      );
    } on GafesoApiException catch (e) {
      // 4xx = refus métier motivé ; on remonte le message du serveur, qui est
      // rédigé pour l'usager. 5xx reste une panne et doit se propager.
      if (e.statusCode >= 500) rethrow;
      return RenewResult(ok: false, reason: _motif(e.body));
    }
  }

  Future<void> cancelHold(String holdId) async =>
      _send('POST', '/reader/holds/$holdId/cancel');

  /// Extrait le message destiné à l'usager d'un corps d'erreur NestJS.
  static String _motif(String body) {
    try {
      final j = jsonDecode(body);
      final m = (j as Map)['message'];
      if (m is String && m.isNotEmpty) return m;
      if (m is List && m.isNotEmpty) return m.join(' · ');
    } catch (_) {
      // Corps non JSON : on ne montre pas de HTML brut à l'écran.
    }
    return 'Renouvellement refusé par la bibliothèque.';
  }

  // ── Catalogue (OPAC) ────────────────────────────────────────────────────

  /// Recherche. `limit` volontairement COURT : un étudiant en 3G paie ses
  /// données, et une page de vingt résultats suffit à décider si l'on affine
  /// ou si l'on fait défiler.
  Future<Object> searchCatalog(String q, {int page = 1, int limit = 20}) async {
    final query = Uri(queryParameters: {
      'q': q,
      'page': '$page',
      'limit': '$limit',
    }).query;
    return (await _send('GET', '/opac/search?$query')) as Object;
  }

  Future<Object> catalogRecord(String id) async =>
      (await _send('GET', '/opac/records/$id')) as Object;

  /// Pose une réservation sur une notice. Comme le renouvellement, un refus
  /// métier est un RÉSULTAT motivé, pas une exception.
  Future<RenewResult> placeHold(String recordId) async {
    try {
      await _send('POST', '/reader/holds', body: {'recordId': recordId});
      return RenewResult(ok: true);
    } on GafesoApiException catch (e) {
      if (e.statusCode >= 500) rethrow;
      return RenewResult(ok: false, reason: _motif(e.body));
    }
  }

  Future<int> downloadBlob({required String url, required File dest}) async {
    final req = await _client.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode >= 400) {
      throw GafesoApiException(res.statusCode, 'téléchargement du blob', url);
    }
    final sink = dest.openWrite();
    await res.pipe(sink);
    return dest.lengthSync();
  }
}

/// Refus de renouvellement, avec son MOTIF.
///
/// Le backend refuse pour des raisons distinctes (plafond atteint, prêt en
/// retard, document réservé par quelqu'un d'autre). Les confondre en « échec »
/// laisserait l'usager sans recours : selon le motif, il doit rendre, attendre,
/// ou ne rien faire du tout.
class RenewResult {
  RenewResult({required this.ok, this.dueDate, this.reason});
  final bool ok;
  final DateTime? dueDate;
  final String? reason;
}

class GafesoApiException implements Exception {
  GafesoApiException(this.statusCode, this.body, this.path);
  final int statusCode;
  final String body;
  final String path;
  @override
  String toString() => 'GafesoApi $statusCode sur $path : $body';
}

/// Licence renvoyée par le backend. `body`/`signature` sont vérifiés NATIVEMENT (Ed25519) ;
/// `wrappedCek` est déballée NATIVEMENT via le keystore (EC-KEM). Dart ne fait que transporter.
class OfflineLicense {
  OfflineLicense({
    required this.licenseId,
    required this.body,
    required this.signature,
    required this.wrappedCek,
    required this.encObjectKey,
    required this.licensePublicKey,
    this.encSegSize,
    this.encAlgo,
  });

  final String licenseId;
  final Map<String, dynamic> body;
  final String signature;
  final String wrappedCek; // JSON EC-KEM {v, epk, nonce, ct}
  final String encObjectKey;
  final String licensePublicKey;
  final int? encSegSize;
  final String? encAlgo;

  String get docId => body['docId'] as String;
  String get tenant => body['tenant'] as String;
  String get userId => body['userId'] as String;
  String get deviceId => body['deviceId'] as String;

  factory OfflineLicense.fromJson(Map<String, dynamic> j) => OfflineLicense(
        licenseId: j['licenseId'] as String,
        body: (j['body'] as Map).cast<String, dynamic>(),
        signature: j['signature'] as String,
        wrappedCek: j['wrappedCek'] as String,
        encObjectKey: j['encObjectKey'] as String,
        licensePublicKey: j['licensePublicKey'] as String,
        encSegSize: j['encSegSize'] as int?,
        encAlgo: j['encAlgo'] as String?,
      );

  /// Corps re-sérialisé tel quel pour la vérification native (le natif canonicalise lui-même).
  String get bodyJson => jsonEncode(body);
}

/// Résultat de connexion : succès, ou étape 2FA que le MVP ne traite pas encore.
class LoginResult {
  const LoginResult._({
    required this.status,
    this.accessToken,
    this.userId,
    this.email,
    this.firstName,
    this.lastName,
    this.role,
  });

  factory LoginResult.success({
    required String accessToken,
    required String userId,
    String? email,
    String? firstName,
    String? lastName,
    String? role,
  }) =>
      LoginResult._(
        status: LoginStatus.success,
        accessToken: accessToken,
        userId: userId,
        email: email,
        firstName: firstName,
        lastName: lastName,
        role: role,
      );

  factory LoginResult.twoFactorRequired() =>
      const LoginResult._(status: LoginStatus.twoFactorRequired);
  factory LoginResult.mustEnroll2fa() =>
      const LoginResult._(status: LoginStatus.mustEnroll2fa);

  final LoginStatus status;
  final String? accessToken;
  final String? userId;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? role;

  bool get isSuccess => status == LoginStatus.success;

  /// Nom lisible pour le filigrane ; repli sur l'email si l'état civil est absent.
  String get displayName {
    final full = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return full.isNotEmpty ? full : (email ?? 'Lecteur');
  }
}

enum LoginStatus { success, twoFactorRequired, mustEnroll2fa }

/// Emplacement temporaire du blob chiffré + paramètres de format.
class BlobLocation {
  BlobLocation({required this.url, this.encSegSize, this.encAlgo});
  final String url;
  final int? encSegSize;
  final String? encAlgo;
}

/// Entrée de l'étagère.
class ShelfDocument {
  ShelfDocument({required this.docId, required this.title, required this.fileFormat});
  final String docId;
  final String title;
  final String fileFormat;
  factory ShelfDocument.fromJson(Map<String, dynamic> j) => ShelfDocument(
        docId: j['docId'] as String,
        title: j['title'] as String,
        fileFormat: j['fileFormat'] as String,
      );
}
