import 'package:flutter/material.dart';

import '../cache/offline_cache.dart';

/// Bandeau de fraîcheur — présent sur CHAQUE écran servi depuis le cache.
///
/// Il répond à la seule question que se pose un usager devant une donnée qu'il
/// n'a pas demandé à rafraîchir : « est-ce à jour ? ». Sans réponse visible,
/// une liste de prêts vieille de trois jours ressemble trait pour trait à une
/// liste à jour — et c'est en la croyant à jour qu'on rate une échéance.
///
/// Trois états, jamais deux :
///   · FRAIS      → rien. Un bandeau permanent devient un décor qu'on ne lit
///                  plus, et qui dilue le signal quand il compte vraiment.
///   · DATÉ       → la date, en langage courant, avec le motif si le dernier
///                  rafraîchissement a échoué.
///   · JAMAIS     → dit explicitement qu'il n'y a rien à montrer, et pourquoi.
///
/// Cas particulier volontaire : une donnée FRAÎCHE dont la mise à jour vient
/// d'échouer affiche quand même le motif. Elle n'est pas « à jour », elle est
/// « à jour à l'instant d'avant » — et l'usager doit pouvoir le savoir avant
/// de se fier à un solde de prêts au comptoir.
class FreshnessBanner extends StatelessWidget {
  const FreshnessBanner({
    super.key,
    required this.syncedAt,
    this.lastError,
    this.onRefresh,
    this.now,
    this.maxAge = Volatility.defaut,
  });

  final DateTime? syncedAt;
  final String? lastError;
  final VoidCallback? onRefresh;

  /// Injectable pour les tests : sans cela, l'assertion dépendrait de l'heure
  /// de la machine et le test deviendrait instable une fois par jour.
  final DateTime? now;

  /// Volatilité de la ressource affichée. `null` = ne vieillit pas, donc aucun
  /// bandeau « daté » (voir `Volatility.carte`).
  final Duration? maxAge;

  @override
  Widget build(BuildContext context) {
    final maintenant = now ?? DateTime.now();
    final etat = Cached<Object>(value: syncedAt == null ? null : 1, syncedAt: syncedAt)
        .freshnessAt(maintenant, maxAge: maxAge);

    if (etat == Freshness.fresh && lastError == null) return const SizedBox.shrink();

    final (couleur, icone, texte) = switch (etat) {
      Freshness.never => (
          Colors.orange.shade100,
          Icons.cloud_off,
          lastError ?? 'Jamais synchronisé — connectez-vous une fois pour voir vos données.',
        ),
      _ => (
          Colors.amber.shade100,
          Icons.history,
          lastError == null
              ? freshnessLabel(syncedAt, maintenant)
              : '${freshnessLabel(syncedAt, maintenant)} · $lastError',
        ),
    };

    return Container(
      width: double.infinity,
      color: couleur,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icone, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(texte, style: const TextStyle(fontSize: 12))),
          if (onRefresh != null)
            TextButton(
              onPressed: onRefresh,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Actualiser', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// Écran vide EXPLIQUÉ — jamais une page blanche.
///
/// Un écran vide laisse l'usager sans recours : il ne sait pas s'il n'a rien,
/// si l'application a échoué, ou si le réseau manque. Chaque état vide doit
/// dire lequel des trois, et quoi faire.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.black54)),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}
