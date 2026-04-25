import 'package:codex_nomad/core/config/app_config.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class SupabaseService {
  SupabaseService(this.config);

  final AppConfig config;

  bool get enabled => config.hasSupabase;

  supabase.SupabaseClient? get _client {
    if (!enabled) return null;
    return supabase.Supabase.instance.client;
  }

  Stream<supabase.AuthState> get authChanges {
    final client = _client;
    if (client == null) return const Stream.empty();
    return client.auth.onAuthStateChange;
  }

  supabase.User? get currentUser => _client?.auth.currentUser;
  String? get accessToken => _client?.auth.currentSession?.accessToken;

  Future<void> sendMagicLink(String email) async {
    final client = _client;
    if (client == null) {
      throw StateError(
          'Supabase is not configured. Provide SUPABASE_URL and SUPABASE_ANON_KEY.');
    }
    await client.auth.signInWithOtp(email: email);
  }

  Future<void> logout() async {
    await _client?.auth.signOut();
  }

  Future<List<SessionSummary>> loadSessions() async {
    final client = _client;
    final user = currentUser;
    if (client == null || user == null) return const [];
    final rows = await client
        .from('session_mappings')
        .select('id, agent, mode, status, updated_at')
        .eq('user_id', user.id)
        .order('updated_at', ascending: false)
        .limit(20);
    return (rows as List).map((row) {
      final json = (row as Map).cast<String, dynamic>();
      return SessionSummary(
        id: json['id'] as String,
        agent: AgentKind.fromWire(json['agent'] as String? ?? 'codex'),
        mode: json['mode'] as String? ?? 'local',
        status: ConnectionStatus.ready,
        lastActivity: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
        machineName: json['machine_name'] as String? ?? 'Local machine',
        machineOs: json['machine_os'] as String? ?? '',
      );
    }).toList();
  }
}
