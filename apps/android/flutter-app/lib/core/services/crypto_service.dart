import 'dart:convert';
import 'dart:typed_data';

import 'package:codex_nomad/core/utils/base64x.dart';
import 'package:sodium/sodium.dart';

class EncryptedMessage {
  const EncryptedMessage({
    required this.type,
    required this.sessionId,
    required this.data,
  });

  final String type;
  final String sessionId;
  final Map<String, dynamic> data;
}

class CryptoService {
  CryptoService._(this._sodium, this._keyPair);

  static Future<CryptoService> create() async {
    final sodium = await SodiumInit.init();
    final keyPair = sodium.crypto.box.keyPair();
    return CryptoService._(sodium, keyPair);
  }

  final Sodium _sodium;
  final KeyPair _keyPair;
  Uint8List? _peerPublicKey;
  int _seq = 0;

  String get publicKey => base64UrlNoPadEncode(_keyPair.publicKey);

  void setPeerPublicKey(String encoded) {
    _peerPublicKey = base64UrlNoPadDecode(encoded);
  }

  Map<String, dynamic> seal({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  }) {
    final peer = _peerPublicKey;
    if (peer == null) {
      throw StateError('Remote public key is missing.');
    }
    _seq += 1;
    final plain = utf8.encode(jsonEncode({
      'type': type,
      'sid': sessionId,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    }));
    final nonce = _sodium.randombytes.buf(_sodium.crypto.box.nonceBytes);
    final cipher = _sodium.crypto.box.easy(
      message: Uint8List.fromList(plain),
      nonce: nonce,
      publicKey: peer,
      secretKey: _keyPair.secretKey,
    );
    return {
      'v': 1,
      'sid': sessionId,
      'sender': 'mobile',
      'seq': _seq,
      'nonce': base64UrlNoPadEncode(nonce),
      'ciphertext': base64UrlNoPadEncode(cipher),
    };
  }

  EncryptedMessage open(Map<String, dynamic> envelope) {
    final peer = _peerPublicKey;
    if (peer == null) {
      throw StateError('Remote public key is missing.');
    }
    final plain = _sodium.crypto.box.openEasy(
      cipherText: base64UrlNoPadDecode(envelope['ciphertext'] as String),
      nonce: base64UrlNoPadDecode(envelope['nonce'] as String),
      publicKey: peer,
      secretKey: _keyPair.secretKey,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return EncryptedMessage(
      type: json['type'] as String,
      sessionId: json['sid'] as String,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  void dispose() {
    _keyPair.dispose();
  }
}
