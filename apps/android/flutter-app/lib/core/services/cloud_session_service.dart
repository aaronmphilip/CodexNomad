import 'dart:convert';

import 'package:codex_nomad/core/config/app_config.dart';
import 'package:codex_nomad/core/services/supabase_service.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:http/http.dart' as http;

class CloudSessionStartResult {
  const CloudSessionStartResult({
    required this.serverId,
    required this.status,
    required this.region,
    required this.estimatedSeconds,
    required this.message,
  });

  factory CloudSessionStartResult.fromJson(Map<String, dynamic> json) {
    return CloudSessionStartResult(
      serverId: json['server_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      region: json['region'] as String? ?? '',
      estimatedSeconds: json['estimated_seconds'] as int? ?? 45,
      message: json['message'] as String? ?? '',
    );
  }

  final String serverId;
  final String status;
  final String region;
  final int estimatedSeconds;
  final String message;
}

class CloudSessionSnapshot {
  const CloudSessionSnapshot({
    required this.serverId,
    required this.status,
    required this.region,
    required this.updatedAt,
    this.daemonSessionId,
    this.repoUrl,
    this.pairing,
  });

  factory CloudSessionSnapshot.fromJson(Map<String, dynamic> json) {
    final pairingRaw = json['pairing_payload'];
    PairingPayload? pairing;
    if (pairingRaw is Map) {
      try {
        pairing = PairingPayload.fromJson(pairingRaw.cast<String, dynamic>());
      } catch (_) {
        pairing = null;
      }
    }
    return CloudSessionSnapshot(
      serverId: json['id'] as String? ?? '',
      status: (json['status'] as String? ?? '').toLowerCase(),
      region: json['region'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      daemonSessionId: json['daemon_session_id'] as String?,
      repoUrl: json['repo_url'] as String?,
      pairing: pairing,
    );
  }

  final String serverId;
  final String status;
  final String region;
  final DateTime updatedAt;
  final String? daemonSessionId;
  final String? repoUrl;
  final PairingPayload? pairing;

  bool get ready => status == 'ready' && pairing != null;
  bool get failed => status == 'failed' || status == 'error';
}

class CloudSessionService {
  const CloudSessionService({
    required this.config,
    required this.supabase,
    http.Client? client,
  }) : _client = client;

  final AppConfig config;
  final SupabaseService supabase;
  final http.Client? _client;

  http.Client get _http => _client ?? http.Client();

  Future<CloudSessionStartResult> start({
    required AgentKind agent,
    String? repoUrl,
    String? country,
  }) async {
    final response = await _http.post(
      Uri.parse('${config.backendBaseUrl}/v1/cloud/sessions/start'),
      headers: _headers(json: true),
      body: jsonEncode({
        'agent': agent.wire,
        if ((repoUrl ?? '').trim().isNotEmpty) 'repo_url': repoUrl!.trim(),
        if ((country ?? '').trim().isNotEmpty) 'country': country!.trim(),
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_errorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final parsed = CloudSessionStartResult.fromJson(json);
    if (parsed.serverId.trim().isEmpty) {
      throw const FormatException('Cloud response did not include server_id.');
    }
    return parsed;
  }

  Future<CloudSessionSnapshot> snapshot(String serverId) async {
    final id = serverId.trim();
    if (id.isEmpty) {
      throw const FormatException('server_id is required');
    }
    final response = await _http.get(
      Uri.parse('${config.backendBaseUrl}/v1/cloud/sessions/$id'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(_errorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return CloudSessionSnapshot.fromJson(json);
  }

  Map<String, String> _headers({bool json = false}) {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    final token = supabase.accessToken;
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
      return headers;
    }
    if (config.appSharedToken.trim().isNotEmpty) {
      headers['X-CodexNomad-Token'] = config.appSharedToken.trim();
    }
    return headers;
  }

  String _errorMessage(http.Response response) {
    final body = response.body.trim();
    if (body.isNotEmpty) {
      return body;
    }
    return 'Request failed (${response.statusCode}).';
  }
}
