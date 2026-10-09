import '../api/gafeso_api.dart';
import 'library_store.dart';

/// Métadonnées d'affichage d'un document : **la route d'abord, l'appareil
/// ensuite**.
///
/// ⚠ POURQUOI UNE FONCTION, ET NON TROIS LIGNES DANS L'ÉTAGÈRE. C'est une
/// RÈGLE, pas un détail de widget : elle décide ce qu'un lecteur voit quand les
/// deux sources divergent, et elle doit pouvoir être éprouvée sans monter un
/// écran. Elle sert aussi à plus d'un endroit (liste, « Lectures en cours »).
///
/// ⚠ L'ORDRE EST LE POINT.
///
///   · La ROUTE (`GET /offline/my-documents`, enrichie depuis le backend rc8)
///     est à jour, mais elle est MUETTE hors ligne.
///   · L'APPAREIL répond toujours, mais ce qu'il garde peut dater.
///
/// Prendre le local en premier figerait un domaine ou un auteur corrigé depuis
/// par le catalogueur. Prendre le distant en premier, mais retomber sur le
/// local dès qu'il ne dit rien, donne le meilleur des deux — et c'est le seul
/// arrangement qui marche aussi dans un amphi sans réseau.
///
/// ⚠ ET LE CAS QUI DÉCIDE DE TOUT : un serveur **antérieur à rc8** ne sert
/// aucun de ces champs. La démonstration tourne en rc7. L'étagère doit alors
/// retomber sur le cache de l'appareil **sans erreur et sans champ vide** —
/// pas afficher trois tirets là où elle connaissait l'auteur hier.
({String? auteur, String? domaine, int? annee}) metadonneesDocument({
  ShelfDocument? distant,
  LocalDocument? local,
}) {
  // « Le distant parle » = il porte AU MOINS UN des trois champs. Un serveur
  // rc7 n'en porte aucun : son entrée existe, elle est simplement muette, et
  // une entrée muette ne doit pas écraser ce que l'appareil sait.
  final distantParle = distant != null &&
      (distant.auteur != null || distant.domaine != null || distant.annee != null);

  // ⚠ Champ par champ, pas en bloc. Un serveur peut servir le domaine et pas
  // l'année ; prendre le distant « tout ou rien » perdrait l'année connue
  // localement pour la seule raison que l'autre champ manquait.
  return (
    auteur: (distantParle ? distant.auteur : null) ?? local?.auteur,
    domaine: (distantParle ? distant.domaine : null) ?? local?.domaine,
    annee: (distantParle ? distant.annee : null) ?? local?.annee,
  );
}
