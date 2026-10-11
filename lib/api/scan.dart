import 'gafeso_api.dart';

/// Ce qu'une adresse scannée s'est révélée être.
///
/// ⚠ QUATRE ISSUES, PAS DEUX. « Introuvable » recouvrirait trois situations qui
/// appellent trois gestes différents : changer d'établissement, scanner le bon
/// code, ou attendre d'avoir du réseau. Les confondre, c'est renvoyer
/// quelqu'un chercher au mauvais endroit.
sealed class ResultatScan {
  const ResultatScan();
}

/// L'adresse est une notice de CETTE école. On a la fiche.
class ScanNotice extends ResultatScan {
  const ScanNotice(this.notice);
  final Object notice;
}

/// ⚠ Le livre existe — ailleurs. Le serveur NOMME l'établissement, pour qu'on
/// dise où aller plutôt que « introuvable ».
class ScanAutreEtablissement extends ResultatScan {
  const ScanAutreEtablissement({required this.message, required this.adresse});

  /// Phrase rédigée par le SERVEUR : lui seul sait quels domaines sont les
  /// siens, et il a déjà écrit le refus.
  final String message;

  /// L'adresse scannée, telle quelle. ⚠ C'est ELLE qu'on proposera d'ouvrir
  /// dans un navigateur — pas un hôte redécoupé du message. Lire une adresse
  /// dans une phrase destinée à un humain, c'est se lier à sa formulation.
  final String adresse;
}

/// Ce n'est pas une adresse de notice Gafeso.
class ScanInconnue extends ResultatScan {
  const ScanInconnue(this.message);
  final String message;
}

/// Pas de réseau, et le document n'est pas sur l'appareil.
class ScanHorsLigne extends ResultatScan {
  const ScanHorsLigne();
}

/// Le document scanné est DÉJÀ sur l'appareil : on l'ouvre, réseau ou pas.
class ScanDejaLa extends ResultatScan {
  const ScanDejaLa(this.docId);
  final String docId;
}

/// Identifiant de notice contenu dans une adresse scannée, ou `null`.
///
/// ⚠ **CE DÉCOUPAGE N'EST PAS LE CHEMIN NORMAL, ET IL NE DOIT PAS LE DEVENIR.**
/// Le serveur a une route pour cela (`GET /opac/scan`), et son commentaire dit
/// pourquoi : une adresse d'un AUTRE établissement se reconnaît à son hôte, et
/// seul le serveur sait quels domaines sont les siens. Un client qui
/// découperait lui-même appellerait sa propre école et dirait « introuvable »
/// alors que le livre existe, ailleurs.
///
/// On ne s'en sert donc que **HORS LIGNE**, où il n'y a personne à qui
/// demander, et uniquement pour reconnaître un document **déjà présent sur
/// l'appareil** — un cas où se tromper d'école est impossible, puisqu'on ne
/// peut avoir emporté que les siens.
String? identifiantDansAdresse(String adresse) {
  final uri = Uri.tryParse(adresse.trim());
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final dernier = uri.pathSegments.last;
  // Un UUID, et rien d'autre : un segment quelconque ferait ouvrir n'importe
  // quoi au premier QR venu.
  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  return uuid.hasMatch(dernier) ? dernier : null;
}

/// Reconnaît une adresse scannée.
///
/// [dejaSurLAppareil] répond « ce document est-il déjà emporté ? » — l'appelant
/// le sait, pas le client HTTP.
Future<ResultatScan> reconnaitreAdresse(
  GafesoApi api,
  String adresse, {
  required bool Function(String docId) dejaSurLAppareil,
}) async {
  try {
    final notice = await api.scan(adresse);
    return ScanNotice(notice);
  } on GafesoApiException catch (e) {
    if (e.statusCode == 409) {
      return ScanAutreEtablissement(
        message: e.motif(
          defaut: 'Ce document appartient à une autre bibliothèque.',
        ),
        adresse: adresse,
      );
    }
    return ScanInconnue(e.motif(
      defaut: 'Cette adresse n’est pas celle d’une notice Gafeso.',
    ));
  } catch (_) {
    // ⚠ RÉSEAU ABSENT — et c'est ici que le hors-ligne se rattrape. Si le
    // document est déjà sur l'appareil, le scanner doit l'ouvrir : c'est
    // précisément la situation d'un étudiant devant un rayonnage, sans data.
    final id = identifiantDansAdresse(adresse);
    if (id != null && dejaSurLAppareil(id)) return ScanDejaLa(id);
    return const ScanHorsLigne();
  }
}
