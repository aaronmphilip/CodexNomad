import 'dart:convert';

import 'package:codex_nomad/core/utils/base64x.dart';

enum AgentKind {
  codex,
  claude;

  static AgentKind fromWire(String value) {
    return value == 'claude' ? AgentKind.claude : AgentKind.codex;
  }

  String get wire => this == AgentKind.claude ? 'claude' : 'codex';
  String get label => this == AgentKind.claude ? 'Claude Code' : 'Codex';
}

class PairingPayload {
  const PairingPayload({
    required this.version,
    required this.sessionId,
    required this.agent,
    required this.mode,
    required this.relayUrl,
    required this.publicKey,
    required this.createdAt,
    required this.expiresAt,
  });

  factory PairingPayload.fromQr(String qr) {
    final uri = Uri.parse(qr);
    final data = uri.queryParameters['data'];
    if (uri.scheme != 'codexnomad' || uri.host != 'pair' || data == null) {
      throw const FormatException('This is not a Codex Nomad pairing QR.');
    }
    final raw = utf8.decode(base64UrlNoPadDecode(data));
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return PairingPayload(
      version: json['v'] as int? ?? 1,
      sessionId: json['sid'] as String,
      agent: AgentKind.fromWire(json['agent'] as String? ?? 'codex'),
      mode: json['mode'] as String? ?? 'local',
      relayUrl: json['relay_url'] as String,
      publicKey: json['public_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  final int version;
  final String sessionId;
  final AgentKind agent;
  final String mode;
  final String relayUrl;
  final String publicKey;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
}
