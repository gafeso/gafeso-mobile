import 'package:flutter/material.dart';

import '../api/server_discovery.dart';
import '../app_state.dart';
import 'qr_scan_screen.dart';

/// Écran 0 — l'adresse du serveur de la bibliothèque.
///
/// Il ne demande PAS l'adresse de l'API : un étudiant n'a aucune raison de la
/// connaître. Il demande l'adresse qu'il a sous les yeux — celle de l'affiche,
/// du QR, du site de sa bibliothèque — et l'application en déduit le reste.
///
/// Deux exigences de sécurité, portées par l'écran plutôt que par un message
/// d'erreur tardif :
///   · HTTPS obligatoire, refusé avec un motif au moment de la saisie ;
///   · le DOMAINE est affiché en clair et l'usager doit confirmer avant qu'on
///     s'y connecte. Après un scan de QR surtout : un code imprimé peut avoir
///     été remplacé sur un mur, et personne ne lit un QR à l'œil. Voir à qui
///     l'on parle est la seule défense possible à cet endroit.
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _controleur = TextEditingController();
  final _decouverte = ServerDiscovery();
  bool _enCours = false;
  String? _erreur;

  @override
  void dispose() {
    _controleur.dispose();
    _decouverte.close();
    super.dispose();
  }

  Future<void> _chercher(String saisie) async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    try {
      final cfg = await _decouverte.resolve(saisie);
      if (!mounted) return;
      setState(() => _enCours = false);
      final confirme = await _confirmer(cfg);
      if (confirme == true) await widget.state.setServer(cfg);
    } on ServerDiscoveryException catch (e) {
      if (mounted) setState(() { _enCours = false; _erreur = e.message; });
    } catch (e) {
      // Filet : aucune exception brute ne doit atteindre l'écran.
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreur = 'Connexion impossible. Vérifiez votre réseau, puis réessayez.';
        });
      }
    }
  }

  /// Confirmation explicite du domaine — jamais de connexion automatique.
  Future<bool?> _confirmer(ServerConfig cfg) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Se connecter à ce serveur ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cfg.schoolName != null) ...[
                Text(cfg.schoolName!, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              const Text('Domaine :'),
              SelectableText(
                cfg.displayHost,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
              ),
              const SizedBox(height: 12),
              const Text(
                'Vos identifiants seront envoyés à ce domaine. '
                'Ne continuez que si vous le reconnaissez.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuer')),
          ],
        ),
      );

  Future<void> _scanner() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code != null && code.isNotEmpty) await _chercher(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Gafeso',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Quelle est votre bibliothèque ?',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              TextField(
                controller: _controleur,
                enabled: !_enCours,
                autocorrect: false,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onSubmitted: _enCours ? null : _chercher,
                decoration: const InputDecoration(
                  labelText: 'Adresse de la bibliothèque',
                  hintText: 'biblio.mon-ecole.bf',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(_erreur!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _enCours ? null : () => _chercher(_controleur.text),
                child: _enCours
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continuer'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _enCours ? null : _scanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scanner le QR de ma bibliothèque'),
              ),
              const SizedBox(height: 24),
              const Text(
                'Le QR est affiché à l’entrée de votre bibliothèque, '
                'sur les tables et en amphi.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
