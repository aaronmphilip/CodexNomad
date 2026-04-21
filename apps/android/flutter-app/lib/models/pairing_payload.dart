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
    required this.machineId,
    required this.machineName,
    required this.machineOs,
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
      machineId: json['machine_id'] as String? ?? '',
      machineName: json['machine_name'] as String? ?? 'Local machine',
      machineOs: json['machine_os'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  factory PairingPayload.fromJson(Map<String, dynamic> json) {
    return PairingPayload(
      version: json['v'] as int? ?? 1,
      sessionId: json['sid'] as String,
      agent: AgentKind.fromWire(json['agent'] as String? ?? 'codex'),
      mode: json['mode'] as String? ?? 'local',
      relayUrl: json['relay_url'] as String,
      publicKey: json['public_key'] as String,
      machineId: json['machine_id'] as String? ?? '',
      machineName: json['machine_name'] as String? ?? 'Local machine',
      machineOs: json['machine_os'] as String? ?? '',
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
  final String machineId;
  final String machineName;
  final String machineOs;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  Map<String, dynamic> toJson() {
    return {
      'v': version,
      'sid': sessionId,
      'agent': agent.wire,
      'mode': mode,
      'relay_url': relayUrl,
      'public_key': publicKey,
      'machine_id': machineId,
      'machine_name': machineName,
      'machine_os': machineOs,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  String encodeForStorage() => jsonEncode(toJson());
}
