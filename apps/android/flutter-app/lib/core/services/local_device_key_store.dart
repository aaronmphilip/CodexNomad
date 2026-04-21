import 'dart:math';
import 'dart:typed_data';

import 'package:codex_nomad/core/utils/base64x.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalDeviceKeyStore {
  LocalDeviceKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _boxSeedKey = 'codex_nomad.mobile_box_seed.v1';
  static const _sequencePrefix = 'codex_nomad.mobile_sequence.v1.';

  final FlutterSecureStorage _storage;

  Future<Uint8List> loadOrCreateBoxSeed(int length) async {
    final existing = await _storage.read(key: _boxSeedKey);
    if (existing != null && existing.isNotEmpty) {
      final seed = base64UrlNoPadDecode(existing);
      if (seed.length == length) return seed;
    }
    final random = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
    await _storage.write(
      key: _boxSeedKey,
      value: base64UrlNoPadEncode(seed),
    );
    return seed;
  }

  Future<int> loadSequence(String sessionId) async {
    final raw = await _storage.read(key: '$_sequencePrefix$sessionId');
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }

  Future<void> saveSequence(String sessionId, int sequence) {
    return _storage.write(
      key: '$_sequencePrefix$sessionId',
      value: sequence.toString(),
    );
  }
}
