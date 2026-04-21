import 'dart:convert';

import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalPairingStore {
  LocalPairingStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _lastPairingKey = 'codex_nomad.last_pairing.v1';

  final FlutterSecureStorage _storage;

  Future<void> saveLastPairing(PairingPayload pairing) {
    return _storage.write(
      key: _lastPairingKey,
      value: pairing.encodeForStorage(),
    );
  }

  Future<PairingPayload?> loadLastPairing() async {
    final raw = await _storage.read(key: _lastPairingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PairingPayload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await clearLastPairing();
      return null;
    }
  }

  Future<void> clearLastPairing() {
    return _storage.delete(key: _lastPairingKey);
  }
}
