import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Découverte du serveur d'un établissement, à partir d'une adresse saisie ou
/// scannée.
///
/// L'URL de l'API n'est plus figée à la compilation. Un APK par établissement
/// interdisait toute publication sur un magasin d'applications, où un seul
/// binaire est publiable.
///
/// ── Le chemin normal ──────────────────────────────────────────────────────
/// L'utilisateur donne l'adresse de sa BIBLIOTHÈQUE (celle du QR, celle de
/// l'affiche, celle qu'il connaît), pas celle de l'API — qu'il n'a aucune
/// raison de connaître. On lit `/.well-known/gafeso.json` sur cette origine
/// pour obtenir l'adresse réelle de l'API, le slug et le nom.
///
/// C'est ce détour qui permet au QR imprimé de ne pas porter l'adresse de
/// l'API : une affiche est un objet physique qui survit à la configuration, et
/// le serveur peut déménager sans qu'on réimprime le bâtiment.
///
/// ── Le repli ──────────────────────────────────────────────────────────────
/// Si le descripteur est absent — installation plus ancienne, adresse d'API
/// donnée directement par un administrateur — on interroge `/health` et on
/// vérifie que la réponse est bien celle d'un Gafeso. Sans cette vérification,
/// une URL erronée produisait une `FormatException` brute : l'utilisateur
/// voyait une trace d'exception au lieu d'un message.

/// Ce qu'il faut savoir pour parler à un établissement.
@immutable
class ServerConfig {
  const ServerConfig({
    required this.apiUrl,
    required this.origin,
    this.tenantSlug,
    this.schoolName,
  });

  /// Adresse publique de l'API (sans barre oblique finale).
  final String apiUrl;

  /// Origine saisie ou scannée — celle que l'utilisateur reconnaît.
  final String origin;

  /// Slug de l'établissement, quand le descripteur ou le QR le donne.
  final String? tenantSlug;

  /// Nom lisible, pour l'écran de confirmation.
  final String? schoolName;

  /// Hôte à MONTRER à l'utilisateur avant de se connecter. C'est le domaine
  /// qu'il doit reconnaître : « à qui suis-je en train de parler ».
  String get displayHost => Uri.parse(origin).host;

  Map<String, dynamic> toJson() => {
        'apiUrl': apiUrl,
        'origin': origin,
        'tenantSlug': tenantSlug,
        'schoolName': schoolName,
      };

  static ServerConfig fromJson(Map<String, dynamic> j) => ServerConfig(
        apiUrl: j['apiUrl'] as String,
        origin: j['origin'] as String,
        tenantSlug: j['tenantSlug'] as String?,
        schoolName: j['schoolName'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ServerConfig &&
      other.apiUrl == apiUrl &&
      other.origin == origin &&
      other.tenantSlug == tenantSlug &&
      other.schoolName == schoolName;

  @override
  int get hashCode => Object.hash(apiUrl, origin, tenantSlug, schoolName);
}

/// Échec de découverte, avec un message DESTINÉ À L'UTILISATEUR.
///
/// Jamais une exception brute remontée à l'écran : « FormatException:
/// Unexpected character » n'apprend rien à un étudiant et le laisse sans
/// recours. Chaque cas dit ce qui ne va pas et ce qu'on peut faire.
class ServerDiscoveryException implements Exception {
  ServerDiscoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ServerDiscovery {
  ServerDiscovery({HttpClient? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  final Duration timeout;

  void close() => _client.close(force: true);

  /// Normalise une saisie en origine utilisable, ou lève un message clair.
  ///
  /// HTTPS EXIGÉ. Le trafic en clair est refusé par la configuration réseau
  /// Android en release ; laisser l'application accepter `http://` produirait
  /// un échec plus tard, au premier appel, avec un message incompréhensible.
  /// Mieux vaut refuser tout de suite en disant pourquoi.
  ///
  /// En debug uniquement, la boucle locale et l'hôte de l'émulateur restent
  /// admis : c'est ce que la configuration réseau du source set debug autorise
  /// déjà, et sans cela aucun développement local n'est possible.
  static Uri normalizeOrigin(String input) {
    var raw = input.trim();
    if (raw.isEmpty) {
      throw ServerDiscoveryException('Saisissez l’adresse de votre bibliothèque.');
    }
    if (!raw.contains('://')) raw = 'https://$raw';

    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      throw ServerDiscoveryException(
        'Adresse incompréhensible. Exemple : biblio.mon-ecole.bf',
      );
    }
    if (uri.scheme != 'https') {
      if (kDebugMode && _isLocal(uri.host)) {
        return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
      }
      throw ServerDiscoveryException(
        'Connexion non chiffrée refusée (${uri.scheme}://). '
        'L’adresse doit commencer par https:// — vos identifiants et vos '
        'documents circuleraient en clair.',
      );
    }
    return Uri(scheme: 'https', host: uri.host, port: uri.hasPort ? uri.port : null);
  }

  static bool _isLocal(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';

  /// Résout une origine en configuration utilisable.
  Future<ServerConfig> resolve(String input) async {
    final origin = normalizeOrigin(input);

    // 1) Descripteur — le chemin normal.
    final descripteur = await _tryDescriptor(origin);
    if (descripteur != null) return descripteur;

    // 2) Repli : l'adresse EST peut-être celle de l'API.
    final sante = await _tryHealth(origin);
    if (sante) {
      return ServerConfig(apiUrl: origin.toString(), origin: origin.toString());
    }

    throw ServerDiscoveryException(
      'Aucun serveur Gafeso à cette adresse (${origin.host}). '
      'Vérifiez l’adresse, ou scannez le QR affiché dans votre bibliothèque.',
    );
  }

  Future<ServerConfig?> _tryDescriptor(Uri origin) async {
    final body = await _getJson(origin.replace(path: '/.well-known/gafeso.json'));
    if (body == null) return null;
    final api = (body['api'] as String?)?.trim();
    // Un descripteur sans adresse d'API est inutilisable. On ne le retient pas :
    // il vaut mieux tenter le repli que d'accepter une configuration creuse qui
    // échouerait au premier appel.
    if (api == null || api.isEmpty) return null;
    return ServerConfig(
      apiUrl: api.replaceAll(RegExp(r'/+$'), ''),
      origin: origin.toString(),
      tenantSlug: (body['tenant'] as String?)?.trim(),
      schoolName: (body['name'] as String?)?.trim(),
    );
  }

  Future<bool> _tryHealth(Uri origin) async {
    final body = await _getJson(origin.replace(path: '/health')) ??
        await _getJson(origin.replace(path: '/api/health'));
    // On vérifie l'IDENTITÉ du service, pas seulement un 200 : n'importe quel
    // serveur répond 200 sur une racine. Sans ce contrôle, l'application se
    // serait « connectée » à un site quelconque et aurait échoué plus tard,
    // sur un JSON qu'elle ne sait pas lire.
    return body != null && body['service'] == 'gafeso-api';
  }

  Future<Map<String, dynamic>?> _getJson(Uri url) async {
    try {
      final req = await _client.getUrl(url).timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final texte = await res.transform(utf8.decoder).join().timeout(timeout);
      final decode = jsonDecode(texte);
      return decode is Map<String, dynamic> ? decode : null;
    } on ServerDiscoveryException {
      rethrow;
    } catch (_) {
      // Panne réseau, TLS refusé, JSON illisible : tous équivalents ici — cette
      // piste n'a pas abouti. L'appelant décidera du message ; on ne laisse
      // surtout pas fuiter une exception brute vers l'écran.
      return null;
    }
  }
}
