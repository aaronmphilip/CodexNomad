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
  });

  final String id;
  final AgentKind agent;
  final String mode;
  final ConnectionStatus status;
  final DateTime lastActivity;
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
    this.openFile,
    this.error,
  });

  final PairingPayload? pairing;
  final ConnectionStatus status;
  final List<TerminalChunk> terminal;
  final List<FileEntry> files;
  final List<DiffCardModel> diffs;
  final CodeFile? openFile;
  final String? error;

  LiveSessionState copyWith({
    PairingPayload? pairing,
    ConnectionStatus? status,
    List<TerminalChunk>? terminal,
    List<FileEntry>? files,
    List<DiffCardModel>? diffs,
    CodeFile? openFile,
    String? error,
  }) {
    return LiveSessionState(
      pairing: pairing ?? this.pairing,
      status: status ?? this.status,
      terminal: terminal ?? this.terminal,
      files: files ?? this.files,
      diffs: diffs ?? this.diffs,
      openFile: openFile ?? this.openFile,
      error: error,
    );
  }
}
