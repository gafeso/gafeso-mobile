import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'screens/login_screen.dart';
import 'screens/shelf_screen.dart';
import 'screens/server_screen.dart';
import 'screens/tenant_screen.dart';

/// URL de l'API FIGÉE au build — désormais OPTIONNELLE.
///
/// L'application demande son serveur au premier lancement et le mémorise : un
/// seul binaire sert tous les établissements, ce qui rend la publication sur un
/// magasin possible (un seul APK y est publiable). Figer l'URL reste utile pour
/// un déploiement white-label mono-établissement : dans ce cas l'écran serveur
/// est sauté.
///
/// La valeur par défaut est VIDE, et non l'hôte de l'émulateur : un défaut
/// pointant vers `10.0.2.2` aurait fait démarrer chaque APK de production sur
/// une adresse de développement injoignable, sans que rien ne l'indique.
const _apiUrl = String.fromEnvironment('GAFESO_API_URL');

/// Expose l'arbre sémantique pour le pilotage automatisé en session device : sans lui,
/// `uiautomator` ne voit aucun widget Flutter (l'arbre n'est construit qu'en présence d'un
/// service d'accessibilité). Gaté par `--dart-define=GAFESO_A11Y_FOR_TESTS=true`, donc absent
/// des builds normaux.
const _a11yForTests = bool.fromEnvironment('GAFESO_A11Y_FOR_TESTS');

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  if (_a11yForTests) binding.ensureSemantics();
  // Répertoire privé de l'app, fourni par le natif (canal com.gafeso/device) : pas de
  // dépendance plugin, et cohérent avec le stockage que lit le lecteur natif.
  final path = await const MethodChannel('com.gafeso/device').invokeMethod<String>('appDir');
  final dir = Directory(path!);
  final state = AppState(apiBaseUrl: _apiUrl.isEmpty ? null : _apiUrl, storageDir: dir);
  await state.restore();
  runApp(GafesoApp(state: state));
}

class GafesoApp extends StatelessWidget {
  const GafesoApp({super.key, this.state});

  final AppState? state;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(colorSchemeSeed: const Color(0xFF0F2B46), useMaterial3: true);
    return MaterialApp(
      title: 'Gafeso',
      theme: theme,
      debugShowCheckedModeBanner: false,
      home: state == null
          // Cas des tests de widgets : pas d'état injecté → écran d'accueil neutre.
          ? const Scaffold(body: Center(child: Text('Gafeso')))
          : _Root(state: state!),
    );
  }
}

/// Aiguillage entre les trois écrans du MVP selon l'étape courante.
class _Root extends StatelessWidget {
  const _Root({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        switch (state.stage) {
          case AppStage.loading:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AppStage.server:
            return ServerScreen(state: state);
          case AppStage.tenant:
            return TenantScreen(onSelected: state.setTenant);
          case AppStage.login:
            return LoginScreen(
              tenantSlug: state.tenantSlug ?? '',
              onLogin: state.login,
              onChangeTenant: state.changeTenant,
              notice: state.sessionNotice,
            );
          case AppStage.shelf:
            return ShelfScreen(state: state);
        }
      },
    );
  }
}
