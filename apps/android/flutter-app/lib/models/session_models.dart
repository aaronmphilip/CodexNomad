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
    this.workspaceRoot = '',
    this.title = '',
  });

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      id: json['id'] as String? ?? '',
      agent: AgentKind.fromWire(json['agent'] as String? ?? 'codex'),
      mode: json['mode'] as String? ?? 'local',
      status: _statusFromName(json['status'] as String?),
      lastActivity: DateTime.tryParse(json['last_activity'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      machineName: json['machine_name'] as String? ?? 'Local machine',
      machineOs: json['machine_os'] as String? ?? '',
      workspaceRoot: json['workspace_root'] as String? ?? '',
      title: json['title'] as String? ?? '',
    );
  }

  final String id;
  final AgentKind agent;
  final String mode;
  final ConnectionStatus status;
  final DateTime lastActivity;
  final String machineName;
  final String machineOs;
  final String workspaceRoot;
  final String title;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'agent': agent.wire,
      'mode': mode,
      'status': status.name,
      'last_activity': lastActivity.toUtc().toIso8601String(),
      'machine_name': machineName,
      'machine_os': machineOs,
      'workspace_root': workspaceRoot,
      'title': title,
    };
  }
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

  String get name {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index < 0) return normalized;
    return normalized.substring(index + 1);
  }

  String get directory {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index < 0) return '.';
    return normalized.substring(0, index);
  }

  Color statusColor(ColorScheme scheme) {
    if (status.contains('A') || status.contains('?')) return Colors.green;
    if (status.contains('D')) return scheme.error;
    if (status.contains('M')) return Colors.amber.shade700;
    return scheme.secondary;
  }
}

class GitSummary {
  const GitSummary({
    this.branch = '',
    this.remote = '',
    this.lastCommit = '',
    this.ahead = 0,
    this.behind = 0,
    this.branches = const [],
    this.changed = const [],
  });

  factory GitSummary.fromJson(Map<String, dynamic> json) {
    final rows = json['changed'];
    return GitSummary(
      branch: json['branch'] as String? ?? '',
      remote: json['remote'] as String? ?? '',
      lastCommit: json['last_commit'] as String? ?? '',
      ahead: json['ahead'] as int? ?? 0,
      behind: json['behind'] as int? ?? 0,
      branches: (json['branches'] as List?)
              ?.whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList() ??
          const [],
      changed: rows is List
          ? rows
              .whereType<Map>()
              .map((row) => FileEntry.fromJson(row.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }

  final String branch;
  final String remote;
  final String lastCommit;
  final int ahead;
  final int behind;
  final List<String> branches;
  final List<FileEntry> changed;

  bool get hasRepo => branch.isNotEmpty || remote.isNotEmpty;
}

class PortEntry {
  const PortEntry({
    required this.port,
    this.protocol = 'tcp',
    this.address = '',
    this.pid = '',
    this.process = '',
    this.url = '',
    this.directUrl = '',
  });

  factory PortEntry.fromJson(Map<String, dynamic> json) {
    return PortEntry(
      port: json['port'] as int? ?? 0,
      protocol: json['protocol'] as String? ?? 'tcp',
      address: json['address'] as String? ?? '',
      pid: json['pid'] as String? ?? '',
      process: json['process'] as String? ?? '',
      url: json['url'] as String? ?? '',
      directUrl: json['direct_url'] as String? ?? '',
    );
  }

  final int port;
  final String protocol;
  final String address;
  final String pid;
  final String process;
  final String url;
  final String directUrl;
}

class PreviewRequestEntry {
  const PreviewRequestEntry({
    this.time,
    this.method = '',
    this.path = '',
    this.status = 0,
    this.durationMs = 0,
    this.error = '',
  });

  factory PreviewRequestEntry.fromJson(Map<String, dynamic> json) {
    return PreviewRequestEntry(
      time: DateTime.tryParse(json['time'] as String? ?? ''),
      method: json['method'] as String? ?? '',
      path: json['path'] as String? ?? '',
      status: json['status'] as int? ?? 0,
      durationMs: json['duration_ms'] as int? ?? 0,
      error: json['error'] as String? ?? '',
    );
  }

  final DateTime? time;
  final String method;
  final String path;
  final int status;
  final int durationMs;
  final String error;
}

class PreviewInspector {
  const PreviewInspector({
    this.enabled = false,
    this.proxyUrl = '',
    this.recentRequests = const [],
  });

  factory PreviewInspector.fromJson(Map<String, dynamic> json) {
    final rows = json['recent_requests'];
    return PreviewInspector(
      enabled: json['enabled'] as bool? ?? false,
      proxyUrl: json['proxy_url'] as String? ?? '',
      recentRequests: rows is List
          ? rows
              .whereType<Map>()
              .map(
                (row) => PreviewRequestEntry.fromJson(
                  row.cast<String, dynamic>(),
                ),
              )
              .toList()
          : const [],
    );
  }

  final bool enabled;
  final String proxyUrl;
  final List<PreviewRequestEntry> recentRequests;
}

class WorkspaceToolsSnapshot {
  const WorkspaceToolsSnapshot({
    this.git = const GitSummary(),
    this.ports = const [],
    this.preview = const PreviewInspector(),
    this.previewUrl = '',
    this.updatedAt,
  });

  factory WorkspaceToolsSnapshot.fromJson(Map<String, dynamic> json) {
    final ports = json['ports'];
    return WorkspaceToolsSnapshot(
      git: GitSummary.fromJson(
        (json['git'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      ports: ports is List
          ? ports
              .whereType<Map>()
              .map((row) => PortEntry.fromJson(row.cast<String, dynamic>()))
              .where((entry) => entry.port > 0)
              .toList()
          : const [],
      preview: PreviewInspector.fromJson(
        (json['preview'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      previewUrl: json['preview_url'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  final GitSummary git;
  final List<PortEntry> ports;
  final PreviewInspector preview;
  final String previewUrl;
  final DateTime? updatedAt;
}

enum ChatRole {
  user,
  agent,
  system,
}

enum ChatDeliveryStatus {
  sending,
  sent,
  failed,
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.delivery = ChatDeliveryStatus.sent,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: _chatRoleFromName(json['role'] as String?),
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      delivery: _deliveryFromName(json['delivery'] as String?),
    );
  }

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
  final ChatDeliveryStatus delivery;

  ChatMessage copyWith({
    String? text,
    ChatDeliveryStatus? delivery,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      createdAt: createdAt,
      delivery: delivery ?? this.delivery,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'text': text,
      'created_at': createdAt.toUtc().toIso8601String(),
      'delivery': delivery.name,
    };
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

  String get name {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index < 0) return normalized;
    return normalized.substring(index + 1);
  }

  String get directory {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index < 0) return '.';
    return normalized.substring(0, index);
  }
}

enum ActivityKind {
  thinking,
  command,
  file,
  review,
  connection,
  complete,
  error,
}

class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.createdAt,
    this.commandCount,
    this.active = false,
  });

  factory ActivityEntry.fromJson(Map<String, dynamic> json) {
    return ActivityEntry(
      id: json['id'] as String? ?? '',
      kind: _activityKindFromName(json['kind'] as String?),
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      commandCount: json['command_count'] as int?,
      active: json['active'] as bool? ?? false,
    );
  }

  final String id;
  final ActivityKind kind;
  final String title;
  final String detail;
  final DateTime createdAt;
  final int? commandCount;
  final bool active;

  ActivityEntry copyWith({
    String? title,
    String? detail,
    int? commandCount,
    bool? active,
  }) {
    return ActivityEntry(
      id: id,
      kind: kind,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      createdAt: createdAt,
      commandCount: commandCount ?? this.commandCount,
      active: active ?? this.active,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'detail': detail,
      'created_at': createdAt.toUtc().toIso8601String(),
      'command_count': commandCount,
      'active': active,
    };
  }
}

class StoredChatSession {
  const StoredChatSession({
    required this.summary,
    required this.chat,
    required this.activity,
  });

  factory StoredChatSession.fromJson(Map<String, dynamic> json) {
    final chatRows = json['chat'];
    final activityRows = json['activity'];
    return StoredChatSession(
      summary: SessionSummary.fromJson(
        (json['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      chat: chatRows is List
          ? chatRows
              .whereType<Map>()
              .map((row) => ChatMessage.fromJson(row.cast<String, dynamic>()))
              .toList()
          : const [],
      activity: activityRows is List
          ? activityRows
              .whereType<Map>()
              .map((row) => ActivityEntry.fromJson(row.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }

  final SessionSummary summary;
  final List<ChatMessage> chat;
  final List<ActivityEntry> activity;

  Map<String, dynamic> toJson() {
    return {
      'summary': summary.toJson(),
      'chat': chat.map((message) => message.toJson()).toList(),
      'activity': activity.map((entry) => entry.toJson()).toList(),
    };
  }
}

class LiveSessionState {
  const LiveSessionState({
    this.pairing,
    this.status = ConnectionStatus.idle,
    this.chat = const [],
    this.activity = const [],
    this.terminal = const [],
    this.files = const [],
    this.diffs = const [],
    this.inbox = const [],
    this.openFile,
    this.openFiles = const [],
    this.openingFilePath,
    this.tools = const WorkspaceToolsSnapshot(),
    this.loadingFiles = false,
    this.loadingTools = false,
    this.gitActionInFlight,
    this.mcpStartupFailed = false,
    this.workspaceRoot = '',
    this.sessionStartedAt,
    this.agentActivity,
    this.error,
  });

  final PairingPayload? pairing;
  final ConnectionStatus status;
  final List<ChatMessage> chat;
  final List<ActivityEntry> activity;
  final List<TerminalChunk> terminal;
  final List<FileEntry> files;
  final List<DiffCardModel> diffs;
  final List<AttentionItem> inbox;
  final CodeFile? openFile;
  final List<CodeFile> openFiles;
  final String? openingFilePath;
  final WorkspaceToolsSnapshot tools;
  final bool loadingFiles;
  final bool loadingTools;
  final String? gitActionInFlight;
  final bool mcpStartupFailed;
  final String workspaceRoot;
  final DateTime? sessionStartedAt;
  final String? agentActivity;
  final String? error;

  static const Object _unset = Object();

  LiveSessionState copyWith({
    Object? pairing = _unset,
    ConnectionStatus? status,
    List<ChatMessage>? chat,
    List<ActivityEntry>? activity,
    List<TerminalChunk>? terminal,
    List<FileEntry>? files,
    List<DiffCardModel>? diffs,
    List<AttentionItem>? inbox,
    Object? openFile = _unset,
    List<CodeFile>? openFiles,
    Object? openingFilePath = _unset,
    WorkspaceToolsSnapshot? tools,
    bool? loadingFiles,
    bool? loadingTools,
    Object? gitActionInFlight = _unset,
    bool? mcpStartupFailed,
    Object? workspaceRoot = _unset,
    Object? sessionStartedAt = _unset,
    Object? agentActivity = _unset,
    Object? error = _unset,
  }) {
    return LiveSessionState(
      pairing: identical(pairing, _unset)
          ? this.pairing
          : pairing as PairingPayload?,
      status: status ?? this.status,
      chat: chat ?? this.chat,
      activity: activity ?? this.activity,
      terminal: terminal ?? this.terminal,
      files: files ?? this.files,
      diffs: diffs ?? this.diffs,
      inbox: inbox ?? this.inbox,
      openFile:
          identical(openFile, _unset) ? this.openFile : openFile as CodeFile?,
      openFiles: openFiles ?? this.openFiles,
      openingFilePath: identical(openingFilePath, _unset)
          ? this.openingFilePath
          : openingFilePath as String?,
      tools: tools ?? this.tools,
      loadingFiles: loadingFiles ?? this.loadingFiles,
      loadingTools: loadingTools ?? this.loadingTools,
      gitActionInFlight: identical(gitActionInFlight, _unset)
          ? this.gitActionInFlight
          : gitActionInFlight as String?,
      mcpStartupFailed: mcpStartupFailed ?? this.mcpStartupFailed,
      workspaceRoot: identical(workspaceRoot, _unset)
          ? this.workspaceRoot
          : workspaceRoot as String,
      sessionStartedAt: identical(sessionStartedAt, _unset)
          ? this.sessionStartedAt
          : sessionStartedAt as DateTime?,
      agentActivity: identical(agentActivity, _unset)
          ? this.agentActivity
          : agentActivity as String?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

ConnectionStatus _statusFromName(String? name) {
  return ConnectionStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => ConnectionStatus.disconnected,
  );
}

ChatRole _chatRoleFromName(String? name) {
  return ChatRole.values.firstWhere(
    (role) => role.name == name,
    orElse: () => ChatRole.system,
  );
}

ChatDeliveryStatus _deliveryFromName(String? name) {
  return ChatDeliveryStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => ChatDeliveryStatus.sent,
  );
}

ActivityKind _activityKindFromName(String? name) {
  return ActivityKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => ActivityKind.thinking,
  );
}
