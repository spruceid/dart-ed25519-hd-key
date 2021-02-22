import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'constants.dart';
import 'key_data.dart';

// Supported curve
const ED25519_HD_KEY = _ED25519HD();

/// Implementation of ED25519 private key derivation from master private key
class _ED25519HD {
  static final _curveBytes = utf8.encode(ED25519_CURVE);
  static final _pathRegex = RegExp(r"^(m\/)?(\d+'?\/)*\d+'?$");

  const _ED25519HD();

  Future<KeyData> derivePath(
    String path,
    Uint8List seedBytes, {
    int offset = HARDENED_OFFSET,
  }) async {
    if (!_ED25519HD._pathRegex.hasMatch(path)) {
      throw ArgumentError(
          "Invalid derivation path. Expected BIP32 path format");
    }

    KeyData master = await getMasterKeyFromSeed(seedBytes);
    List<String> segments = path.split('/');
    segments = segments.sublist(1);

    return await Stream.fromIterable(segments).fold<Future<KeyData>>(
      Future.sync(() => master),
      (prevKeyData, indexStr) async {
        int index = int.parse(indexStr.substring(0, indexStr.length - 1));
        return await _getCKDPriv(await prevKeyData, index + offset);
      },
    );
  }

  Future<Uint8List> getPublicKey(
    Uint8List privateKey, [
    bool withZeroByte = true,
  ]) async {
    final signature = await Ed25519().newKeyPairFromSeed(privateKey);
    final pk = await signature.extractPublicKey();
    if (withZeroByte == true) {
      Uint8List dataBytes = Uint8List(33);
      dataBytes[0] = 0x00;
      dataBytes.setRange(1, 33, pk.bytes);
      return dataBytes;
    } else {
      return pk.bytes;
    }
  }

  Future<KeyData> getMasterKeyFromSeed(Uint8List seedBytes) async =>
      await _getKeys(seedBytes, _ED25519HD._curveBytes);

  Future<KeyData> _getCKDPriv(KeyData data, int index) async {
    Uint8List dataBytes = Uint8List(37);
    dataBytes[0] = 0x00;
    dataBytes.setRange(1, 33, data.key);
    dataBytes.buffer.asByteData().setUint32(33, index);
    return await _getKeys(dataBytes, Uint8List.fromList(data.chainCode));
  }

  Future<KeyData> _getKeys(Uint8List data, Uint8List keyParameter) async {
    final hmac =
        await Hmac.sha512().newMacSink(secretKey: SecretKey(keyParameter));

    hmac
      ..add(data)
      ..close();

    final mac = await hmac.mac();
    final I = mac.bytes;
    final IL = I.sublist(0, 32);
    final IR = I.sublist(32);

    return KeyData(key: IL, chainCode: IR);
  }
}
