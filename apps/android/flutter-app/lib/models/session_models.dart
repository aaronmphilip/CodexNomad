import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:flutter/material.dart';

enum ConnectionStatus {
  idle,
  pairing,
  connecting,
  ready,
  disconnected,
  ended,
  error,
}

class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.agent,
    required this.mode,
    required this.status,
    required this.lastActivity,
    this.machineName = 'Local machine',
    this.machineOs = '',
  });

  final String id;
  final AgentKind agent;
  final String mode;
  final ConnectionStatus status;
  final DateTime lastActivity;
  final String machineName;
  final String machineOs;
}

class TerminalChunk {
  const TerminalChunk({
    required this.text,
    required this.createdAt,
    this.isError = false,
  });

  final String text;
  final DateTime createdAt;
  final bool isError;
}

class FileEntry {
  const FileEntry({
    required this.path,
    required this.status,
    this.size,
    this.modified,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      path: json['path'] as String? ?? '',
      status: json['status'] as String? ?? 'tracked',
      size: json['size'] as int?,
      modified: json['modified'] == null
          ? null
          : DateTime.tryParse(json['modified'] as String),
    );
  }

  final String path;
  final String status;
  final int? size;
  final DateTime? modified;

  Color statusColor(ColorScheme scheme) {
    if (status.contains('A') || status.contains('?')) return Colors.green;
    if (status.contains('D')) return scheme.error;
    if (status.contains('M')) return Colors.amber.shade700;
    return scheme.secondary;
  }
}

class DiffCardModel {
  const DiffCardModel({
    required this.filePath,
    required this.summary,
    required this.patch,
  });

  final String filePath;
  final String summary;
  final String patch;
}

enum AttentionKind {
  permission,
  diff,
  blocked,
  complete,
  connection,
  error,
}

enum AttentionTone {
  info,
  success,
  warning,
  danger,
}

class AttentionItem {
  const AttentionItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.tone = AttentionTone.info,
    this.actionLabel,
  });

  factory AttentionItem.fromEvent({
    required String type,
    required Map<String, dynamic> data,
  }) {
    final now = DateTime.now();
    return switch (type) {
      'permission_requested' => AttentionItem(
          id: data['id'] as String? ??
              'permission-${now.microsecondsSinceEpoch}',
          kind: AttentionKind.permission,
          title: data['title'] as String? ?? 'Permission requested',
          detail: data['detail'] as String? ?? 'The agent needs approval.',
          createdAt: now,
          tone: _toneForRisk(data['risk'] as String?),
          actionLabel: 'Review',
        ),
      'diff_ready' => AttentionItem(
          id: 'diff-${data['file_path'] ?? now.microsecondsSinceEpoch}',
          kind: AttentionKind.diff,
          title: 'Diff ready',
          detail:
              data['summary'] as String? ?? 'Working tree changes are ready.',
          createdAt: now,
          tone: AttentionTone.info,
          actionLabel: 'Open',
        ),
      'process_exit' => AttentionItem(
          id: 'exit-${now.microsecondsSinceEpoch}',
          kind: AttentionKind.complete,
          title: 'Agent finished',
          detail: (data['error'] as String?)?.isNotEmpty == true
              ? data['error'] as String
              : 'The local session ended.',
          createdAt: now,
          tone: (data['error'] as String?)?.isNotEmpty == true
              ? AttentionTone.warning
              : AttentionTone.success,
        ),
      'disconnect' => AttentionItem(
          id: 'disconnect-${now.microsecondsSinceEpoch}',
          kind: AttentionKind.connection,
          title: 'Connection dropped',
          detail: data['error'] as String? ?? 'Reconnect to the local machine.',
          createdAt: now,
          tone: AttentionTone.warning,
        ),
      'error' => AttentionItem(
          id: 'error-${now.microsecondsSinceEpoch}',
          kind: AttentionKind.error,
          title: 'Session error',
          detail: data['message'] as String? ?? 'The local session failed.',
          createdAt: now,
          tone: AttentionTone.danger,
        ),
      _ => AttentionItem(
          id: '$type-${now.microsecondsSinceEpoch}',
          kind: AttentionKind.blocked,
          title: type,
          detail: '$data',
          createdAt: now,
          tone: AttentionTone.info,
        ),
    };
  }

  final String id;
  final AttentionKind kind;
  final String title;
  final String detail;
  final DateTime createdAt;
  final AttentionTone tone;
  final String? actionLabel;
}

AttentionTone _toneForRisk(String? risk) {
  return switch (risk) {
    'high' => AttentionTone.danger,
    'medium' => AttentionTone.warning,
    _ => AttentionTone.info,
  };
}

class CodeFile {
  const CodeFile({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;
}

class LiveSessionState {
  const LiveSessionState({
    this.pairing,
    this.status = ConnectionStatus.idle,
    this.terminal = const [],
    this.files = const [],
    this.diffs = const [],
    this.inbox = const [],
    this.openFile,
    this.error,
  });

  final PairingPayload? pairing;
  final ConnectionStatus status;
  final List<TerminalChunk> terminal;
  final List<FileEntry> files;
  final List<DiffCardModel> diffs;
  final List<AttentionItem> inbox;
  final CodeFile? openFile;
  final String? error;

  LiveSessionState copyWith({
    PairingPayload? pairing,
    ConnectionStatus? status,
    List<TerminalChunk>? terminal,
    List<FileEntry>? files,
    List<DiffCardModel>? diffs,
    List<AttentionItem>? inbox,
    CodeFile? openFile,
    String? error,
  }) {
    return LiveSessionState(
      pairing: pairing ?? this.pairing,
      status: status ?? this.status,
      terminal: terminal ?? this.terminal,
      files: files ?? this.files,
      diffs: diffs ?? this.diffs,
      inbox: inbox ?? this.inbox,
      openFile: openFile ?? this.openFile,
      error: error,
    );
  }
}
