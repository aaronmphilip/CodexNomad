import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:codex_nomad/core/utils/base64x.dart';
import 'package:cryptography/cryptography.dart';

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
  CryptoService._({
    required X25519 x25519,
    required Xchacha20 cipher,
    required SimpleKeyPair keyPair,
    required SimplePublicKey publicKey,
    required int initialSequence,
  })  : _x25519 = x25519,
        _cipher = cipher,
        _keyPair = keyPair,
        _publicKey = publicKey,
        _seq = initialSequence;

  static Future<CryptoService> create({
    Uint8List? seed,
    int initialSequence = 0,
  }) async {
    final x25519 = X25519();
    final keySeed = seed ?? _randomBytes(boxSeedBytes);
    final keyPair = await x25519.newKeyPairFromSeed(keySeed);
    final publicKey = await keyPair.extractPublicKey();
    return CryptoService._(
      x25519: x25519,
      cipher: Xchacha20.poly1305Aead(),
      keyPair: keyPair,
      publicKey: publicKey,
      initialSequence: initialSequence,
    );
  }

  static int get boxSeedBytes => 32;

  final X25519 _x25519;
  final Xchacha20 _cipher;
  final SimpleKeyPair _keyPair;
  final SimplePublicKey _publicKey;
  SimplePublicKey? _peerPublicKey;
  SecretKey? _sharedKey;
  int _seq;
  int _lastPeerSeq = 0;

  String get publicKey => base64UrlNoPadEncode(_publicKey.bytes);
  int get sequence => _seq;

  Future<void> setPeerPublicKey(String encoded) async {
    final peer = SimplePublicKey(
      base64UrlNoPadDecode(encoded),
      type: KeyPairType.x25519,
    );
    _peerPublicKey = peer;
    _sharedKey = await _x25519.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: peer,
    );
  }

  Future<Map<String, dynamic>> seal({
    required String sessionId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    final key = _sharedKey;
    if (key == null || _peerPublicKey == null) {
      throw StateError('Remote public key is missing.');
    }
    _seq += 1;
    final sequence = _seq;
    final plain = utf8.encode(jsonEncode({
      'type': type,
      'sid': sessionId,
      'seq': sequence,
      'sent_at': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    }));
    final nonce = _randomBytes(_cipher.nonceLength);
    final box = await _cipher.encrypt(
      plain,
      secretKey: key,
      nonce: nonce,
    );
    return {
      'v': 1,
      'sid': sessionId,
      'sender': 'mobile',
      'seq': sequence,
      'nonce': base64UrlNoPadEncode(box.nonce),
      'ciphertext': base64UrlNoPadEncode(box.concatenation(nonce: false)),
    };
  }

  Future<EncryptedMessage> open(Map<String, dynamic> envelope) async {
    final key = _sharedKey;
    if (key == null || _peerPublicKey == null) {
      throw StateError('Remote public key is missing.');
    }
    final envelopeSeq = _readInt(envelope['seq']);
    final combined = base64UrlNoPadDecode(envelope['ciphertext'] as String);
    final boxParts = SecretBox.fromConcatenation(
      combined,
      nonceLength: 0,
      macLength: _cipher.macAlgorithm.macLength,
      copy: false,
    );
    final box = SecretBox(
      boxParts.cipherText,
      nonce: base64UrlNoPadDecode(envelope['nonce'] as String),
      mac: boxParts.mac,
    );
    final plain = await _cipher.decrypt(box, secretKey: key);
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    final envelopeSessionId = envelope['sid'] as String? ?? '';
    final plainSessionId = json['sid'] as String? ?? '';
    final plainSeq = _readInt(json['seq']);
    if (envelopeSessionId.isNotEmpty && plainSessionId != envelopeSessionId) {
      throw StateError('Encrypted session id does not match envelope.');
    }
    if (plainSeq != envelopeSeq) {
      throw StateError('Encrypted sequence does not match envelope.');
    }
    if (envelopeSeq <= _lastPeerSeq) {
      throw StateError('Replayed or out-of-order agent message.');
    }
    _lastPeerSeq = envelopeSeq;
    return EncryptedMessage(
      type: json['type'] as String,
      sessionId: plainSessionId,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? {},
    );
  }

  void dispose() {
    _keyPair.destroy();
  }

  int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
