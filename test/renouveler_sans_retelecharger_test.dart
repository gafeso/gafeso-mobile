import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gafeso_mobile/api/gafeso_api.dart';
import 'package:gafeso_mobile/api/offline_service.dart';

/// ⚠ **RENOUVELER UN BAIL NE DOIT PAS REPRENDRE LE FICHIER.**
///
/// Une licence expire au bout de quelques jours ; le document, lui, n'a pas
/// changé. Reprendre le blob à chaque renouvellement ferait repayer tout le
/// document — plusieurs dizaines de Mo pour une thèse — sur une connexion
/// comptée au mégaoctet, pour obtenir des octets déjà présents sur l'appareil.
///
/// Le garde tient en une ligne dans `OfflineService.download` : le blob n'est
/// demandé que si le fichier local est absent ou vide. Une ligne qu'une
/// « simplification » enlève sans que rien ne casse visiblement — l'app
/// marcherait toujours, elle coûterait seulement cher. C'est exactement le
/// genre de régression qu'un test doit tenir.
class _ApiFactice extends GafesoApi {
  _ApiFactice() : super(baseUrl: 'http://127.0.0.1:1', tenantSlug: 'test');

  int licencesEmises = 0;
  int urlsDemandees = 0;
  int blobsTelecharges = 0;

  @override
  Future<String> registerDevice({
    required String publicKeySpkiB64,
    String? label,
    String platform = 'android',
  }) async =>
      'dev-1';

  @override
  Future<OfflineLicense> issueLicense({
    required String docId,
    required String deviceId,
  }) async {
    licencesEmises++;
    return OfflineLicense(
      licenseId: 'lic-$licencesEmises',
      body: {
        'docId': docId,
        'tenant': 'test',
        'userId': 'u-1',
        'deviceId': deviceId,
      },
      signature: 'sig',
      wrappedCek: '{"v":1}',
      encObjectKey: 'k',
      licensePublicKey: 'pk',
    );
  }

  @override
  Future<BlobLocation> blobUrl(String licenseId) async {
    urlsDemandees++;
    return BlobLocation(url: 'http://exemple.invalide/$licenseId');
  }

  @override
  Future<int> downloadBlob({required String url, required File dest}) async {
    blobsTelecharges++;
    dest.writeAsBytesSync(List<int>.filled(4096, 7)); // un blob non vide
    return 4096;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Map<String, String> coffre;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gafeso-renouv-');
    coffre = {};
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('com.gafeso/device'), (call) async {
      switch (call.method) {
        case 'isRegistered':
          return coffre.containsKey('deviceId');
        case 'storeDeviceId':
          coffre['deviceId'] = (call.arguments as Map)['deviceId'] as String;
          return true;
        case 'deviceId':
          return coffre['deviceId'];
        case 'publicKey':
          return 'cle-publique';
      }
      return null;
    });
    m.setMockMethodCallHandler(const MethodChannel('com.gafeso/secure'), (call) async {
      final nom = (call.arguments as Map?)?['name'] as String?;
      switch (call.method) {
        case 'get':
          return coffre[nom];
        case 'put':
          coffre[nom!] = (call.arguments as Map)['value'] as String;
          return true;
        case 'remove':
          coffre.remove(nom);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('⚠ le renouvellement reprend la LICENCE, pas le fichier', () async {
    final api = _ApiFactice();
    final service = OfflineService(api: api, storageDir: tmp);

    await service.download(docId: 'doc-1', title: 'Une thèse');
    expect(api.blobsTelecharges, 1, reason: 'premier emport : le fichier vient');

    await service.download(docId: 'doc-1', title: 'Une thèse');

    expect(api.licencesEmises, 2, reason: 'un nouveau bail est bien demandé');
    expect(api.blobsTelecharges, 1, reason: 'LE FICHIER NE DOIT PAS REVENIR');
    expect(api.urlsDemandees, 1,
        reason: 'on ne demande même pas l’URL : rien ne part sur le réseau');
  });

  test('⚠ témoin — un fichier ABSENT est bien repris', () async {
    // Sans ce cas, le test ci-dessus passerait aussi si `download` ne
    // téléchargeait JAMAIS rien.
    final api = _ApiFactice();
    final service = OfflineService(api: api, storageDir: tmp);

    await service.download(docId: 'doc-2', title: 'Un mémoire');
    File('${tmp.path}/doc-2.gafs').deleteSync();
    await service.download(docId: 'doc-2', title: 'Un mémoire');

    expect(api.blobsTelecharges, 2);
  });

  test('⚠ témoin — un fichier VIDE est repris, pas tenu pour bon', () async {
    // Un téléchargement interrompu laisse un fichier de 0 octet. Le considérer
    // comme présent donnerait un document définitivement illisible, que rien
    // ne répare — l'échec le plus coûteux, celui qui ne se signale pas.
    final api = _ApiFactice();
    final service = OfflineService(api: api, storageDir: tmp);

    await service.download(docId: 'doc-3', title: 'Un ouvrage');
    File('${tmp.path}/doc-3.gafs').writeAsBytesSync([]);
    await service.download(docId: 'doc-3', title: 'Un ouvrage');

    expect(api.blobsTelecharges, 2);
  });
}
