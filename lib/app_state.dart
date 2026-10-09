import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api/gafeso_api.dart';
import 'cache/cover_cache.dart';
import 'api/server_discovery.dart';
import 'api/offline_service.dart';
import 'session/progress_store.dart';
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

  /// Message à présenter sur l'écran de connexion après une session perdue.
  /// Effacé dès qu'une connexion réussit.
  String? sessionNotice;

  /// Modules actifs de l'établissement, `null` tant qu'on ne sait pas.
  ///
  /// ⚠ `null` ≠ « aucun module ». Tant que la réponse n'est pas là (ou qu'elle a
  /// échoué), l'app montre TOUT : amputer un menu sur une incertitude est pire
  /// que de montrer une entrée de trop, parce que l'usager ne sait pas qu'il
  /// manque quelque chose et ne peut pas le demander.
  Set<String>? modulesActifs;

  /// La circulation physique est-elle en service ici ?
  ///
  /// Une université virtuelle n'a ni comptoir, ni exemplaire, ni carte à
  /// présenter. Lui afficher « Mes prêts » promettrait un service absent.
  /// Le serveur a REFUSÉ une route de circulation en disant que le module est
  /// inactif. Signal plus sûr que `GET /modules` : il vient de la route même
  /// que l'entrée de menu allait ouvrir. Une fois posé, il ne se relève qu'au
  /// changement d'école ou de session — un établissement ne rouvre pas un
  /// comptoir pendant qu'on consulte son étagère.
  bool circulationRefusee = false;

  /// ⚠ **SOURCE DE VÉRITÉ** : `circulationActive` de `GET /tenancy/current`
  /// (backend rc6). Servi SANS jeton, donc disponible avant même la connexion.
  ///
  /// `null` = le serveur ne publie pas le champ, ou on ne l'a pas encore lu.
  /// Trois états, et le troisième compte : « je ne sais pas » n'est pas « il
  /// n'y a pas de comptoir ».
  bool? circulationDuServeur;

  /// La circulation physique est-elle en service ici ?
  ///
  /// ⚠ L'ORDRE DES SOURCES EST LE CORRECTIF. Le refus de route était seul juge,
  /// et il est IRRÉVERSIBLE pour la session : un refus transitoire d'une
  /// milliseconde amputait le menu d'un établissement qui a bel et bien un
  /// comptoir, jusqu'à la relance de l'app — constaté une fois sur
  /// `recette-etu@`, qui a pourtant un prêt et une réservation.
  ///
  /// Désormais : si le serveur répond, SA réponse tranche, et le refus de route
  /// ne pèse plus rien. Le repli par refus ne sert qu'aux serveurs antérieurs à
  /// rc6, qui ne publient pas le champ.
  bool get circulationActive {
    final duServeur = circulationDuServeur;
    if (duServeur != null) return duServeur;
    return !circulationRefusee &&
        (modulesActifs == null || modulesActifs!.contains('circulation'));
  }

  /// Titre de l'étagère.
  ///
  /// Sans circulation physique, « étagère » et « prêt » n'ont pas de référent :
  /// l'usager ne reçoit rien au comptoir, il consulte des documents que son
  /// établissement lui ouvre. Le mot doit le dire.
  ///
  /// ⚠ COURT, ET C'EST MESURÉ. « Mes documents hors ligne » demande 534 dp à la
  /// taille d'un titre de barre : il ne tient sur AUCUN écran de 360 dp, quelle
  /// que soit la taille de police et même sans une seule icône. Le qualificatif
  /// « hors ligne » vit donc dans le corps de l'écran — l'état vide le dit, et
  /// chaque ligne téléchargée porte « Disponible hors ligne ».
  String get titreEtagere =>
      circulationActive ? 'Mon étagère' : 'Mes documents';

  /// Prend acte du refus. Silencieux par construction : l'absence d'un module
  /// n'est pas une panne, et il n'y a RIEN à annoncer à l'usager — on retire
  /// une promesse qu'on n'aurait pas dû faire, on ne lui signale pas un échec.
  void circulationInactive() {
    // ⚠ Un refus ne contredit pas le serveur. S'il a dit que la circulation est
    // active, c'est lui qui a raison : le refus vient d'ailleurs — droit
    // personnel, incident passager — et amputer le menu serait une faute.
    if (circulationDuServeur == true) return;
    if (circulationRefusee) return;
    circulationRefusee = true;
    notifyListeners();
  }

  /// ⚠ **UN SIGNAL POSITIF ANNULE LA BASCULE.** Une route `/reader/*` qui
  /// répond 200 prouve qu'il y a un comptoir, quoi qu'un refus antérieur ait
  /// laissé croire. Sans cela, le premier hoquet du serveur condamnait le menu
  /// jusqu'à la relance.
  void circulationConfirmee() {
    if (!circulationRefusee) return;
    circulationRefusee = false;
    circulationDuServeur = null;
    notifyListeners();
  }

  /// Lit la source de vérité. Silencieux, et sans jeton : l'app peut la
  /// connaître avant la connexion.
  Future<void> chargerCirculation() async {
    final v = await _api?.circulationPublique();
    if (v == null) return; // on ne sait pas : on ne change rien
    if (v == circulationDuServeur) return;
    circulationDuServeur = v;
    if (v) circulationRefusee = false;
    notifyListeners();
  }

  /// Progression de lecture — **locale à l'appareil**, jamais envoyée.
  /// Voir `ProgressStore` : savoir où quelqu'un en est de sa lecture est une
  /// information intime, et le service rendu ne demande pas qu'un serveur la
  /// connaisse.
  final ProgressStore progression = ProgressStore();

  /// Cache disque des couvertures. Créé une fois : il survit aux écrans, c'est
  /// tout son intérêt (une vignette vue hier s'affiche hors ligne aujourd'hui).
  late final CoverCache covers = CoverCache(dossier: storageDir);

  /// Origine du serveur — sert à résoudre les couvertures en chemin relatif,
  /// servies par le SITE et non par l'API.
  String? get origineServeur => server?.origin;
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
      unawaited(_chargerModules());
      unawaited(chargerCirculation());
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
    // Le client détecte la perte de session (401, ou `membersOnly` sur un 200) ;
    // l'état applicatif en tire la conséquence, une seule fois.
    _api!.onSessionPerdue = () => unawaited(sessionExpiree());
    _api!.onCirculationInactive = circulationInactive;
    _api!.onCirculationConfirmee = circulationConfirmee;
    _offline = OfflineService(api: _api!, storageDir: storageDir);
  }

  /// Demande l'état des modules et rafraîchit l'affichage s'il a changé.
  /// Silencieux : l'app est utilisable avant la réponse, et sans elle.
  Future<void> _chargerModules() async {
    final m = await _api?.modulesActifs();
    if (m == null) return;
    modulesActifs = m;
    notifyListeners();
  }

  /// SESSION PERDUE — le jeton ne vaut plus rien, et on le DIT.
  ///
  /// Le jeton vit un jour et il n'y a pas de renouvellement : au lendemain
  /// d'une connexion, l'app mentait sur deux écrans sans jamais ramener
  /// personne vers la connexion. Ici on nomme la cause, et on ramène.
  ///
  /// ⚠ AUCUNE PURGE, ET C'EST LA DIFFÉRENCE AVEC [logout].
  /// Une déconnexion est un choix : le lecteur rend l'appareil, le contenu part
  /// avec. Une expiration n'est le choix de personne — effacer la bibliothèque
  /// hors ligne à chaque jeton périmé détruirait tous les jours le seul travail
  /// que le produit existe pour rendre possible : lire sans réseau.
  ///
  /// Idempotente : plusieurs requêtes en vol signalent la même perte.
  Future<void> sessionExpiree() async {
    if (session == null) return;
    await sessions.clearSession();
    session = null;
    _wire(tenantSlug!);
    sessionNotice =
        'Votre session a expiré. Reconnectez-vous pour retrouver le catalogue. '
        'Les documents déjà téléchargés restent sur l’appareil.';
    stage = AppStage.login;
    notifyListeners();
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
          sessionNotice = null;
          // L'état des modules conditionne le menu : on le demande une fois,
          // juste après la connexion, sans bloquer l'entrée dans l'app.
          unawaited(_chargerModules());
      unawaited(chargerCirculation());
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
    await covers.vider();
    modulesActifs = null;
    circulationRefusee = false;
    circulationDuServeur = null;
    await sessions.clearSession();
    session = null;
    _wire(tenantSlug!);
    stage = AppStage.login;
    notifyListeners();
  }

  /// Changement d'école : tout est réinitialisé.
  Future<void> changeTenant() async {
    await _offline?.purgeEverything();
    // ⚠ Les couvertures d'une école n'ont rien à faire dans une autre.
    await covers.vider();
    modulesActifs = null;
    circulationRefusee = false;
    circulationDuServeur = null;
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
