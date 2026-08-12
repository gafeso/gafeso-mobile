import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Écran de lecture : hôte de la **PlatformView native** (Étape 1). Tout ce qui touche au
/// déchiffrement, à la vérification de licence et au rendu se passe côté natif — aucune page
/// ne remonte vers Dart. `FLAG_SECURE` est posé sur la fenêtre par `MainActivity`.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key, required this.title, required this.params});

  final String title;
  final Map<String, dynamic> params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: AndroidView(
        viewType: 'gafeso-pdf-reader',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
