import 'dart:convert';

import 'package:flutter/services.dart';

/// Un document rendu disponible hors-ligne : sa licence (nécessaire pour ouvrir SANS réseau)
/// et le chemin du blob chiffré.
class LocalDocument {
  const LocalDocument({
    required this.docId,
    required this.title,
    required this.licenseId,
    required this.licenseBody,
    required this.signature,
    required this.licensePublicKey,
    required this.wrappedCek,
    required this.blobPath,
    this.lastStatus = 'active',
  });

  final String docId;
  final String title;
  final String licenseId;
  final String licenseBody; // JSON canonique-able du corps signé
  final String signature;
  final String licensePublicKey;
  final String wrappedCek; // enveloppe EC-KEM {v, epk, nonce, ct}
  final String blobPath;
  final String lastStatus;

  Map<String, dynamic> toJson() => {
        'docId': docId,
        'title': title,
        'licenseId': licenseId,
        'licenseBody': licenseBody,
        'signature': signature,
        'licensePublicKey': licensePublicKey,
        'wrappedCek': wrappedCek,
        'blobPath': blobPath,
        'lastStatus': lastStatus,
      };

  factory LocalDocument.fromJson(Map<String, dynamic> j) => LocalDocument(
        docId: j['docId'] as String,
        title: j['title'] as String,
        licenseId: j['licenseId'] as String,
        licenseBody: j['licenseBody'] as String,
        signature: j['signature'] as String,
        licensePublicKey: j['licensePublicKey'] as String,
        wrappedCek: j['wrappedCek'] as String,
        blobPath: j['blobPath'] as String,
        lastStatus: (j['lastStatus'] as String?) ?? 'active',
      );

  LocalDocument copyWith({String? lastStatus}) => LocalDocument(
        docId: docId,
        title: title,
        licenseId: licenseId,
        licenseBody: licenseBody,
        signature: signature,
        licensePublicKey: licensePublicKey,
        wrappedCek: wrappedCek,
        blobPath: blobPath,
        lastStatus: lastStatus ?? this.lastStatus,
      );
}

/// Bibliothèque locale — **chiffrée par le keystore** (canal `com.gafeso/secure`) : elle
/// contient les licences, donc les CEK enveloppées. Persister la licence est ce qui rend la
/// lecture possible **sans réseau** ; le blob seul ne suffit pas.
class LibraryStore {
  LibraryStore({MethodChannel? channel})
      : _ch = channel ?? const MethodChannel('com.gafeso/secure');

  static const _key = 'library';
  final MethodChannel _ch;

  Future<Map<String, LocalDocument>> readAll() async {
    final raw = await _ch.invokeMethod<String>('get', {'name': _key});
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {
        for (final e in map.entries)
          e.key: LocalDocument.fromJson((e.value as Map).cast<String, dynamic>()),
      };
    } catch (_) {
      await _ch.invokeMethod('remove', {'name': _key});
      return {};
    }
  }

  Future<void> _writeAll(Map<String, LocalDocument> docs) async {
    await _ch.invokeMethod('put', {
      'name': _key,
      'value': jsonEncode({for (final e in docs.entries) e.key: e.value.toJson()}),
    });
  }

  Future<void> upsert(LocalDocument doc) async {
    final all = await readAll();
    all[doc.docId] = doc;
    await _writeAll(all);
  }

  Future<LocalDocument?> get(String docId) async => (await readAll())[docId];

  Future<void> remove(String docId) async {
    final all = await readAll();
    all.remove(docId);
    await _writeAll(all);
  }

  Future<void> clear() => _ch.invokeMethod('remove', {'name': _key}).then((_) {});
}
