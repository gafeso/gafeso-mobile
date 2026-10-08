import 'package:flutter/material.dart';

import '../theme/gafeso_theme.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../session/tenant_code.dart';

/// Lecture du **QR de l'école** par la caméra. Ne fait qu'une chose : renvoyer le premier code
/// dont la charge utile contient un slug valide (`TenantCode.parse`, déjà couvert par les
/// tests). Tout QR non reconnu est ignoré silencieusement — l'usager continue de viser.
///
/// La permission caméra est demandée par le plugin au premier démarrage du contrôleur ; en cas
/// de refus, l'écran l'explique et propose la saisie manuelle.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      // ON REND LA CHARGE UTILE BRUTE, PAS LE SLUG EXTRAIT.
      //
      // Cet écran rendait auparavant le slug. C'était juste tant que le seul
      // appelant n'avait besoin que de lui — mais l'écran serveur, lui, a
      // besoin de l'ORIGINE (`https://bibliotheque.exemple.bf/e/gafeso-univ`) pour
      // aller lire /.well-known/gafeso.json. Rendre `gafeso-univ` la détruisait :
      // l'application tentait de joindre `https://gafeso-univ`, un hôte qui
      // n'existe pas, et affichait « aucun serveur à cette adresse » alors que
      // le QR était parfaitement valide. Constaté en recette d'appareil.
      //
      // Chaque appelant extrait désormais ce dont il a besoin. Un scanner ne
      // doit pas décider à la place de qui l'appelle.
      if (TenantCode.parse(raw) != null || TenantCode.origin(raw) != null) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le QR de l’école')),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              _error = switch (error.errorCode) {
                MobileScannerErrorCode.permissionDenied =>
                  'Accès à la caméra refusé. Autorisez-le, ou saisissez le code à la main.',
                _ => 'Caméra indisponible : saisissez le code de l’école à la main.',
              };
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Saisir le code'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // Viseur : simple repère visuel, aucune logique.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: context.gafeso.surCamera.withValues(alpha: 0.7), width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Text(
                'Visez le QR affiché au comptoir',
                style: TextStyle(color: context.gafeso.surCamera, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
