import 'dart:convert';

import 'package:flutter/services.dart';

import '../api/server_discovery.dart';

/// Session offline de l'usager. Contient le strict nécessaire au fonctionnement hors-ligne :
/// le tenant, le jeton, l'identité (pour la liaison de licence) et le **nom d'affichage
/// utilisé par le filigrane** du lecteur. Aucun mot de passe n'est conservé.
class AppSession {
  const AppSession({
    required this.tenantSlug,
    required this.token,
    required this.userId,
    required this.displayName,
    this.email,
    this.role,
  });

  final String tenantSlug;
  final String token;
  final String userId;
  final String displayName;
  final String? email;
  final String? role;

  Map<String, dynamic> toJson() => {
        'tenantSlug': tenantSlug,
        'token': token,
        'userId': userId,
        'displayName': displayName,
        'email': ?email,
        'role': ?role,
      };

  factory AppSession.fromJson(Map<String, dynamic> j) => AppSession(
        tenantSlug: j['tenantSlug'] as String,
        token: j['token'] as String,
        userId: j['userId'] as String,
        displayName: j['displayName'] as String,
        email: j['email'] as String?,
        role: j['role'] as String?,
      );

  /// Texte de filigrane incrusté au rendu (identifie le lecteur sur chaque page).
  String watermark(DateTime now) {
    final stamp = now.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    return '$displayName · $tenantSlug · $stamp';
  }
}

/// Persistance de la session **chiffrée par le keystore** (canal natif `com.gafeso/secure`)
/// et du slug de tenant choisi. Le tenant est gardé séparément : il est connu avant le login
/// (écran 1) et sert d'en-tête `X-Tenant` dès les premiers appels.
class SessionStore {
  SessionStore({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('com.gafeso/secure');

  static const _kSession = 'session';
  static const _kTenant = 'tenant';
  // Serveur découvert (adresse d'API, origine, école). Gardé à part de la
  // session : il survit à une déconnexion — l'usager reste dans SON
  // établissement et n'a pas à ressaisir l'adresse pour se reconnecter.
  static const _kServer = 'server';

  final MethodChannel _ch;

  Future<String?> readTenant() => _ch.invokeMethod<String>('get', {'name': _kTenant});

  Future<void> writeTenant(String slug) async {
    await _ch.invokeMethod('put', {'name': _kTenant, 'value': slug});
  }

  Future<ServerConfig?> readServer() async {
    final raw = await _ch.invokeMethod<String>('get', {'name': _kServer});
    if (raw == null || raw.isEmpty) return null;
    try {
      return ServerConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Enregistrement illisible (format changé, écriture interrompue) : on
      // repart de l'écran serveur plutôt que de propager une exception au
      // démarrage, écran sur lequel l'usager n'aurait aucun recours.
      await _ch.invokeMethod('remove', {'name': _kServer});
      return null;
    }
  }

  Future<void> writeServer(ServerConfig cfg) async {
    await _ch.invokeMethod('put', {'name': _kServer, 'value': jsonEncode(cfg.toJson())});
  }

  Future<AppSession?> read() async {
    final raw = await _ch.invokeMethod<String>('get', {'name': _kSession});
    if (raw == null || raw.isEmpty) return null;
    try {
      return AppSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clearSession();
      return null;
    }
  }

  Future<void> write(AppSession session) async {
    await _ch.invokeMethod('put', {'name': _kSession, 'value': jsonEncode(session.toJson())});
    await writeTenant(session.tenantSlug);
  }

  /// Déconnexion : efface la session, garde le tenant (l'usager reste dans son école).
  Future<void> clearSession() => _ch.invokeMethod('remove', {'name': _kSession}).then((_) {});

  /// Réinitialisation complète (changement d'école).
  Future<void> clearAll() => _ch.invokeMethod('clear').then((_) {});
}
