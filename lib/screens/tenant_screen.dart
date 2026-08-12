import 'package:flutter/material.dart';

import '../session/tenant_code.dart';
import 'qr_scan_screen.dart';

/// Écran 1 — **sélection de l'école**. Saisie du code (slug) ou lecture du QR présenté au
/// comptoir. Le code retenu devient l'en-tête `X-Tenant` de tous les appels.
///
/// Deux chemins équivalents : saisie manuelle, ou **scan caméra** du QR (`QrScanScreen`).
/// Dans les deux cas `TenantCode.parse` décode la charge utile — slug nu,
/// `gafeso://tenant/<slug>`, URL d'école, `?tenant=` — et refuse ce qui n'est pas un slug valide.
class TenantScreen extends StatefulWidget {
  const TenantScreen({super.key, required this.onSelected, this.scanner});

  final Future<void> Function(String slug) onSelected;

  /// Source du code scanné. Par défaut : l'écran caméra (`QrScanScreen`). Injectable pour
  /// tester le câblage « charge utile → décodage → sélection » sans caméra.
  final Future<String?> Function(BuildContext context)? scanner;

  @override
  State<TenantScreen> createState() => _TenantScreenState();
}

class _TenantScreenState extends State<TenantScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final slug = TenantCode.parse(_controller.text);
    if (slug == null) {
      setState(() => _error = 'Code d’école invalide. Exemple : « zinda ».');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.onSelected(slug);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.local_library_outlined, size: 64),
                const SizedBox(height: 12),
                Text(
                  'Gafeso',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'La maison des livres',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                const Text('Entrez le code de votre école, ou scannez le QR au comptoir.'),
                const SizedBox(height: 12),
                TextField(
                  controller: _controller,
                  autocorrect: false,
                  enabled: !_busy,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'Code de l’école',
                    hintText: 'zinda',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    prefixIcon: const Icon(Icons.school_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Continuer'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _scanQr(context),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanner le QR de l’école'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ouvre la caméra pour lire le QR de l'école. Le décodage de la charge utile (tous
  /// formats) est assuré par `TenantCode.parse`, déjà couvert par les tests ; si la caméra
  /// est indisponible ou refusée, l'écran de scan renvoie null et l'usager saisit le code.
  Future<void> _scanQr(BuildContext context) async {
    final scan = widget.scanner ?? _openCamera;
    final payload = await scan(context);
    if (payload == null || !mounted) return;
    // La charge utile passe par le même décodage que la saisie manuelle.
    _controller.text = payload;
    await _submit();
  }

  Future<String?> _openCamera(BuildContext context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const QrScanScreen()),
      );
}
