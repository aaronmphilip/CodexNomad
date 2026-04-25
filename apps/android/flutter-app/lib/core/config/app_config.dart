import 'package:flutter_riverpod/flutter_riverpod.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.backendBaseUrl,
    required this.appSharedToken,
    required this.enableCloudProvisioning,
  });

  factory AppConfig.fromEnvironment() {
    return const AppConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
      backendBaseUrl: String.fromEnvironment(
        'CODEXNOMAD_BACKEND_URL',
        defaultValue: 'http://10.0.2.2:8080',
      ),
      appSharedToken: String.fromEnvironment('CODEXNOMAD_APP_TOKEN'),
      enableCloudProvisioning: bool.fromEnvironment(
        'CODEXNOMAD_ENABLE_CLOUD',
      ),
    );
  }

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String backendBaseUrl;
  final String appSharedToken;
  final bool enableCloudProvisioning;

  bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
