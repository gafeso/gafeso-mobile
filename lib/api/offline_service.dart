import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../session/library_store.dart';
import 'gafeso_api.dart';

/// Orchestration du cœur offline : relie le client HTTP, le keystore natif, la bibliothèque
/// locale chiffrée et le lecteur.
///
/// Répartition des rôles — Dart ne voit **jamais** de secret en clair :
///   - natif : garde la clé EC (keystore), déballe la CEK (EC-KEM), vérifie la licence
///     (Ed25519) et rend le PDF ; chiffre la bibliothèque locale ;
///   - Dart : transporte les octets (licence signée, enveloppe, blob chiffré) et pilote l'UI.
class OfflineService {
  OfflineService({
    required this.api,
    required this.storageDir,
    LibraryStore? library,
    MethodChannel? deviceChannel,
  })  : library = library ?? LibraryStore(),
        _device = deviceChannel ?? const MethodChannel('com.gafeso/device');

  final GafesoApi api;
  final Directory storageDir;
  final LibraryStore library;
  final MethodChannel _device;

  // ── Appareil ────────────────────────────────────────────────────────────────
  Future<String> devicePublicKey() async =>
      (await _device.invokeMethod<String>('publicKey'))!;

  Future<String> deviceId() async => (await _device.invokeMethod<String>('deviceId'))!;

  Future<bool> isRegistered() async =>
      (await _device.invokeMethod<bool>('isRegistered')) ?? false;

  /// Enregistre l'appareil auprès du backend et **persiste l'identifiant attribué** (celui que
  /// la licence lie et qui sert d'AAD). Idempotent.
  Future<String> ensureDeviceRegistered({String? label}) async {
    if (await isRegistered()) return deviceId();
    final publicKey = await devicePublicKey();
    final serverId = await api.registerDevice(publicKeySpkiB64: publicKey, label: label);
    await _device.invokeMethod('storeDeviceId', {'deviceId': serverId});
    return serverId;
  }

  // ── Mise à disposition hors-ligne ───────────────────────────────────────────
  /// Télécharge un document pour la lecture hors-ligne : licence émise + blob chiffré + entrée
  /// de bibliothèque persistée (c'est elle qui permet d'ouvrir ensuite SANS réseau).
  Future<LocalDocument> download({
    required String docId,
    required String title,
    String? auteur,
    String? domaine,
    int? annee,
    String? type,
  }) async {
    final devId = await ensureDeviceRegistered();
    final license = await api.issueLicense(docId: docId, deviceId: devId);

    final dest = File('${storageDir.path}/$docId.gafs');
    if (!dest.existsSync() || dest.lengthSync() == 0) {
      final blob = await api.blobUrl(license.licenseId);
      await api.downloadBlob(url: blob.url, dest: dest);
    }

    // ⚠ On ne PERD pas ce qu'on savait déjà. Un renouvellement part souvent de
    // l'étagère, qui n'a que le titre : écraser l'auteur et le domaine recopiés
    // au premier téléchargement appauvrirait la fiche à chaque renouvellement.
    final ancien = (await library.readAll())[docId];
    final doc = LocalDocument(
      docId: docId,
      title: title,
      auteur: auteur ?? ancien?.auteur,
      domaine: domaine ?? ancien?.domaine,
      annee: annee ?? ancien?.annee,
      type: type ?? ancien?.type,
      licenseId: license.licenseId,
      licenseBody: license.bodyJson,
      signature: license.signature,
      licensePublicKey: license.licensePublicKey,
      wrappedCek: license.wrappedCek,
      blobPath: dest.path,
    );
    await library.upsert(doc);
    return doc;
  }

  /// Paramètres à passer à la PlatformView du lecteur — lus depuis la bibliothèque LOCALE,
  /// donc disponibles hors-ligne. `null` si le document n'est pas (ou plus) téléchargé.
  Future<Map<String, dynamic>?> openParams({
    required String docId,
    required String watermark,
  }) async {
    final doc = await library.get(docId);
    if (doc == null) return null;
    if (!File(doc.blobPath).existsSync()) {
      await library.remove(docId);
      return null;
    }
    return {
      'blobPath': doc.blobPath,
      'licenseBody': doc.licenseBody,
      'signature': doc.signature,
      'licensePublicKey': doc.licensePublicKey,
      'wrappedCek': doc.wrappedCek,
      'userId': _userIdOf(doc.licenseBody),
      'tenant': _tenantOf(doc.licenseBody),
      'watermark': watermark,
    };
  }

  // ── Re-check de statut / purge ──────────────────────────────────────────────
  /// Re-vérifie le statut d'un document et **purge** s'il n'est plus actif.
  Future<String> refreshStatus(String docId) async {
    final doc = await library.get(docId);
    if (doc == null) return 'absent';
    final status = await api.licenseStatus(doc.licenseId);
    if (status == 'active' || status == 'unknown') {
      // `unknown` = le serveur ne sait pas. On conserve (voir refreshAll).
      await library.upsert(doc.copyWith(lastStatus: status));
    } else {
      await purge(docId);
    }
    return status;
  }

  /// Re-check en LOT à la reconnexion (une requête) ; purge tout ce qui n'est plus actif.
  /// Renvoie les statuts par docId.
  Future<Map<String, String>> refreshAll() async {
    final all = await library.readAll();
    if (all.isEmpty) return {};
    final byLicense = {for (final d in all.values) d.licenseId: d.docId};
    final statuses = await api.entitlements(byLicense.keys.toList());
    final out = <String, String>{};
    for (final e in statuses.entries) {
      final docId = byLicense[e.key];
      if (docId == null) continue;
      out[docId] = e.value;
      if (e.value == 'active') {
        final d = all[docId];
        if (d != null) await library.upsert(d.copyWith(lastStatus: e.value));
      } else if (e.value == 'unknown') {
        // Le serveur ne connaît PAS cette licence. Ce n'est pas une
        // révocation : c'est une absence d'information — restauration d'une
        // sauvegarde antérieure à l'émission, base réinitialisée, licence
        // perdue. On CONSERVE le document et on redemandera plus tard.
        //
        // Purger ici détruisait l'ouvrage d'un étudiant en lui annonçant qu'il
        // « n'est plus accessible », alors que personne n'avait rien révoqué.
        // Seule une révocation ou une expiration RÉELLE justifie de détruire.
        final d = all[docId];
        if (d != null) await library.upsert(d.copyWith(lastStatus: e.value));
      } else {
        await purge(docId);
      }
    }
    return out;
  }

  /// Purge locale : blob chiffré supprimé + licence (donc la CEK enveloppée) oubliée.
  Future<void> purge(String docId) async {
    final doc = await library.get(docId);
    if (doc != null) {
      final f = File(doc.blobPath);
      if (f.existsSync()) await f.delete();
    }
    await library.remove(docId);
  }

  Future<void> purgeEverything() async {
    for (final docId in (await library.readAll()).keys.toList()) {
      await purge(docId);
    }
    await library.clear();
  }

  // Le corps de licence est un JSON ; on n'y lit que des champs non sensibles (la vérification
  // de signature et les liaisons, elles, sont faites par le NATIF avant tout rendu).
  String _userIdOf(String body) => _field(body, 'userId');
  String _tenantOf(String body) => _field(body, 'tenant');
  String _field(String json, String name) {
    try {
      final map = (jsonDecode(json) as Map).cast<String, dynamic>();
      return (map[name] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }
}
