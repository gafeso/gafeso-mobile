import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Écran « À propos » — il sert d'abord à répondre à UNE question :
/// **quelle variante de l'application est installée sur ce téléphone ?**
///
/// ⚠ Les deux variantes portaient le même numéro de version. Sur un appareil
/// réel, une capture d'écran qui passait ne permettait donc pas de distinguer un
/// défaut du blocage de la variante construite exprès pour l'autoriser. Ici,
/// l'app le dit elle-même, sans câble et sans outil.
class AProposScreen extends StatefulWidget {
  const AProposScreen({super.key, this.infos});

  /// Injectable pour les tests ; sinon lu du canal natif.
  final Future<Map<Object?, Object?>?> Function()? infos;

  @override
  State<AProposScreen> createState() => _AProposScreenState();
}

class _AProposScreenState extends State<AProposScreen> {
  Map<Object?, Object?>? _infos;
  bool _charge = false;

  @override
  void initState() {
    super.initState();
    _lire();
  }

  Future<void> _lire() async {
    final lecture = widget.infos ??
        () => const MethodChannel('com.gafeso/device')
            .invokeMapMethod<Object?, Object?>('buildInfo');
    try {
      final i = await lecture();
      if (mounted) setState(() { _infos = i; _charge = true; });
    } catch (_) {
      if (mounted) setState(() => _charge = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = _infos;
    final capturesOuvertes = i?['capturesAutorisees'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text('À propos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Gafeso', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('La maison des livres', style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 24),

          if (!_charge)
            const Text('Lecture des informations…')
          else if (i == null)
            const Text('Informations de version indisponibles.')
          else ...[
            _ligne('Version', '${i['versionName']}'),
            _ligne('Build', '${i['versionCode']}'),
            _ligne('Variante', i['debug'] == true ? 'débogage' : 'publication'),
            const SizedBox(height: 20),

            // ⚠ LE POINT DE CET ÉCRAN.
            if (capturesOuvertes)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border(left: BorderSide(color: Colors.red.shade700, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: Colors.red.shade800),
                      const SizedBox(width: 8),
                      Text('Capture d’écran AUTORISÉE',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade900)),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                      'Cette version a été construite pour produire les images de la fiche du '
                      'magasin. Elle ne protège pas les documents contre la capture et NE DOIT '
                      'PAS être distribuée ni utilisée pour lire des documents réels.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border(left: BorderSide(color: Colors.green.shade700, width: 3)),
                ),
                child: Row(children: [
                  Icon(Icons.shield_outlined, size: 18, color: Colors.green.shade800),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Capture d’écran bloquée — version normale.',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
          ],

          const SizedBox(height: 28),
          const Text(
            'Logiciel libre sous licence AGPL-3.0.\n'
            'Édité par ResurgiTech, Ouagadougou.',
            style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _ligne(String libelle, String valeur) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90,
                child: Text(libelle, style: const TextStyle(fontSize: 13, color: Colors.black54))),
            Expanded(child: SelectableText(valeur, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}
