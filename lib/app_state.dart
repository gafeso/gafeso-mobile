import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/gafeso_api.dart';
import 'api/server_discovery.dart';
import 'api/offline_service.dart';
import 'session/session.dart';

/// Étape du parcours MVP : école → connexion → étagère.
/// Étape du parcours : serveur → école → connexion → étagère.
///
/// `server` précède tout : sans adresse, l'application ne sait à qui parler.
/// Elle n'est demandée qu'UNE fois — ensuite elle est mémorisée, et une
/// déconnexion ne la fait pas oublier.
enum AppStage { loading, server, tenant, login, shelf }

/// État applicatif du MVP. Détient la session (chiffrée localement), le client API et le
/// service offline, et expose l'étape courante à l'UI.
///
/// L'URL de l'API est fournie au build (`--dart-define=GAFESO_API_URL=…`) : en production
/// chaque école a son domaine, mais l'app mobile parle à l'API directe avec l'en-tête
/// `X-Tenant` (le middleware backend le résout).
class AppState extends ChangeNotifier {
  AppState({
    String? apiBaseUrl,
    required this.storageDir,
    SessionStore? sessionStore,
  })  : _fixedApiUrl = apiBaseUrl,
        sessions = sessionStore ?? SessionStore();

  /// URL figée au build (`--dart-define=GAFESO_API_URL=…`), pour un
  /// déploiement white-label mono-établissement. Quand elle est fournie,
  /// l'écran serveur est sauté : le binaire n'est destiné qu'à une école.
  final String? _fixedApiUrl;

  ServerConfig? server;

  /// Adresse de l'API réellement utilisée.
  String get apiBaseUrl => _fixedApiUrl ?? server?.apiUrl ?? '';
  final Directory storageDir;
  final SessionStore sessions;

  AppStage stage = AppStage.loading;
  String? tenantSlug;
  AppSession? session;
  String? lastError;

  GafesoApi? _api;
  OfflineService? _offline;

  GafesoApi get api => _api!;
  OfflineService get offline => _offline!;
  bool get isReady => _api != null;

  /// Restaure l'état persistant au démarrage (école + session) — l'app doit être utilisable
  /// hors-ligne dès l'ouverture si une session existe.
  Future<void> restore() async {
    server = await sessions.readServer();
    if (_fixedApiUrl == null && server == null) {
      stage = AppStage.server;
      notifyListeners();
      return;
    }
    tenantSlug = await sessions.readTenant();
    session = await sessions.read();
    if (session != null) {
      tenantSlug = session!.tenantSlug;
      _wire(session!.tenantSlug, token: session!.token);
      stage = AppStage.shelf;
    } else if (tenantSlug != null) {
      _wire(tenantSlug!);
      stage = AppStage.login;
    } else {
      // Le descripteur donne souvent déjà l'école : inutile de la redemander.
      final duServeur = server?.tenantSlug;
      if (duServeur != null && duServeur.isNotEmpty) {
        tenantSlug = duServeur;
        _wire(duServeur);
        stage = AppStage.login;
      } else {
        stage = AppStage.tenant;
      }
    }
    notifyListeners();
  }

  void _wire(String slug, {String? token}) {
    _api?.close();
    _api = GafesoApi(baseUrl: apiBaseUrl, tenantSlug: slug, token: token);
    _offline = OfflineService(api: _api!, storageDir: storageDir);
  }

  /// Écran 0 — serveur confirmé par l'usager (après affichage du domaine).
  Future<void> setServer(ServerConfig cfg) async {
    server = cfg;
    await sessions.writeServer(cfg);
    final slug = cfg.tenantSlug;
    if (slug != null && slug.isNotEmpty) {
      await setTenant(slug);
    } else {
      stage = AppStage.tenant;
      lastError = null;
      notifyListeners();
    }
  }

  /// Écran 1 — école choisie (saisie ou QR).
  Future<void> setTenant(String slug) async {
    tenantSlug = slug;
    await sessions.writeTenant(slug);
    _wire(slug);
    stage = AppStage.login;
    lastError = null;
    notifyListeners();
  }

  /// Écran 2 — connexion. Renvoie `null` si OK, sinon un message affichable.
  Future<String?> login({required String email, required String password}) async {
    try {
      final res = await api.login(email: email, password: password);
      switch (res.status) {
        case LoginStatus.twoFactorRequired:
          return 'Double authentification requise : non prise en charge par l’application '
              'mobile pour l’instant. Connectez-vous depuis le site.';
        case LoginStatus.mustEnroll2fa:
          return 'Votre école exige l’activation de la double authentification. '
              'Faites-le depuis le site, puis revenez.';
        case LoginStatus.success:
          final s = AppSession(
            tenantSlug: tenantSlug!,
            token: res.accessToken!,
            userId: res.userId!,
            displayName: res.displayName,
            email: res.email,
            role: res.role,
          );
          await sessions.write(s);
          session = s;
          _wire(s.tenantSlug, token: s.token);
          stage = AppStage.shelf;
          notifyListeners();
          return null;
      }
    } on GafesoApiException catch (e) {
      return e.statusCode == 401
          ? 'Identifiants incorrects.'
          : 'Connexion impossible (${e.statusCode}).';
    } catch (e) {
      return 'Connexion impossible : $e';
    }
  }

  /// Déconnexion : session effacée, contenu local purgé (la licence part avec).
  Future<void> logout() async {
    await _offline?.purgeEverything();
    await sessions.clearSession();
    session = null;
    _wire(tenantSlug!);
    stage = AppStage.login;
    notifyListeners();
  }

  /// Changement d'école : tout est réinitialisé.
  Future<void> changeTenant() async {
    await _offline?.purgeEverything();
    await sessions.clearAll();
    session = null;
    tenantSlug = null;
    _api?.close();
    _api = null;
    _offline = null;
    stage = AppStage.tenant;
    notifyListeners();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }
}
