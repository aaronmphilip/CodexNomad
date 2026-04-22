import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OnboardingStore {
  OnboardingStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _completedKey = 'codex_nomad.onboarding_completed.v1';

  final FlutterSecureStorage _storage;

  Future<bool> loadCompleted() async {
    final value = await _storage.read(key: _completedKey);
    return value == 'true';
  }

  Future<void> saveCompleted(bool completed) {
    return _storage.write(
        key: _completedKey, value: completed ? 'true' : 'false');
  }
}
