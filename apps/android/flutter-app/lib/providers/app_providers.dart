import 'dart:async';
import 'dart:convert';

import 'package:codex_nomad/core/config/app_config.dart';
import 'package:codex_nomad/core/services/local_chat_history_store.dart';
import 'package:codex_nomad/core/services/local_pairing_store.dart';
import 'package:codex_nomad/core/services/notification_service.dart';
import 'package:codex_nomad/core/services/onboarding_store.dart';
import 'package:codex_nomad/core/services/relay_service.dart';
import 'package:codex_nomad/core/services/supabase_service.dart';
import 'package:codex_nomad/core/services/voice_service.dart';
import 'package:codex_nomad/core/utils/base64x.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService(ref.watch(appConfigProvider));
});

final voiceServiceProvider = Provider<VoiceService>((ref) {
  return VoiceService();
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  unawaited(service.initialize());
  return service;
});

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(ref.watch(supabaseServiceProvider));
});

final onboardingControllerProvider =
    ChangeNotifierProvider<OnboardingController>((ref) {
  return OnboardingController();
});

final sessionControllerProvider =
    ChangeNotifierProvider<SessionController>((ref) {
  return SessionController(
    ref.watch(appConfigProvider),
    ref.watch(notificationServiceProvider),
  );
});

class OnboardingController extends ChangeNotifier {
  OnboardingController({OnboardingStore? store})
      : _store = store ?? OnboardingStore() {
    unawaited(_load());
  }

  final OnboardingStore _store;
  bool _loaded = false;
  bool _completed = false;

  bool get loaded => _loaded;
  bool get completed => _completed;

  Future<void> complete() async {
    _loaded = true;
    _completed = true;
    notifyListeners();
    await _store.saveCompleted(true);
  }

  Future<void> reset() async {
    _loaded = true;
    _completed = false;
    notifyListeners();
    await _store.saveCompleted(false);
  }

  Future<void> _load() async {
    try {
      _completed = await _store.loadCompleted().timeout(
            const Duration(milliseconds: 900),
            onTimeout: () => false,
          );
    } catch (_) {
      _completed = false;
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }
}

class AuthController extends ChangeNotifier {
  AuthController(this._supabase);

  final SupabaseService _supabase;
  bool _busy = false;
  String? _message;

  bool get busy => _busy;
  String? get message => _message;
  bool get configured => _supabase.enabled;
  bool get signedIn => _supabase.currentUser != null;
  String? get email => _supabase.currentUser?.email;

  Future<void> sendMagicLink(String email) async {
    _busy = true;
    _message = null;
    notifyListeners();
    try {
      await _supabase.sendMagicLink(email);
      _message = 'Magic link sent. Open it on this device.';
    } catch (error) {
      _message = '$error';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _supabase.logout();
    notifyListeners();
  }
}

class SessionController extends ChangeNotifier {
  SessionController(AppConfig config, this._notifications)
      : _relay = RelayService(config) {
    _relaySub = _relay.events.listen(_handleEvent);
    unawaited(_restoreHistory());
    unawaited(_restoreLastPairing());
  }

  final RelayService _relay;
  final NotificationService _notifications;
  final LocalPairingStore _pairingStore = LocalPairingStore();
  final LocalChatHistoryStore _historyStore = LocalChatHistoryStore();
  StreamSubscription<RelayEvent>? _relaySub;
  LiveSessionState _state = const LiveSessionState();
  final List<SessionSummary> _recentSessions = [];
  PairingPayload? _lastPairing;
  String? _currentSessionId;
  int _messageCounter = 0;
  int _activityCounter = 0;
  int _commandCounter = 0;
  bool _reportedMcpStartupIssue = false;
  String? _pendingPromptId;
  String? _queuedLaunchPrompt;
  bool _queuedLaunchPromptSending = false;
  Timer? _autoReconnectTimer;
  int _autoReconnectAttempt = 0;
  bool _sessionEndedByUser = false;

  LiveSessionState get state => _state;
  List<SessionSummary> get recentSessions => List.unmodifiable(_recentSessions);
  PairingPayload? get lastPairing => _lastPairing;
  String? get currentSessionId => _currentSessionId;
  String? get queuedLaunchPrompt => _queuedLaunchPrompt;

  void queueLaunchPrompt(String prompt) {
    final value = prompt.trim();
    _queuedLaunchPrompt = value.isEmpty ? null : value;
    notifyListeners();
  }

  Future<void> connectFromQr(String rawQr) async {
    final pairing = PairingPayload.fromQr(rawQr);
    await connectFromPairing(pairing);
  }

  Future<void> connectFromPairing(
    PairingPayload pairing, {
    bool saveAsLastPairing = true,
  }) async {
    _sessionEndedByUser = false;
    _resetAutoReconnect();
    _reportedMcpStartupIssue = false;
    _queuedLaunchPromptSending = false;
    final started = DateTime.now();
    _currentSessionId = pairing.sessionId;
    _state = LiveSessionState(
      pairing: pairing,
      status: ConnectionStatus.connecting,
      sessionStartedAt: started,
      activity: [
        _newActivity(
          kind: ActivityKind.connection,
          title: 'Connecting',
          detail: 'Pairing phone with ${pairing.agent.label}.',
          active: true,
        ),
      ],
      agentActivity: 'Connecting to ${pairing.agent.label}...',
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.connect(pairing);
      if (saveAsLastPairing) {
        _lastPairing = pairing;
        unawaited(_pairingStore.saveLastPairing(pairing));
      }
      _remember(pairing, ConnectionStatus.connecting);
      _persistCurrentHistory();
    } catch (error) {
      _state = _state.copyWith(
        status: ConnectionStatus.error,
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Connection failed',
            detail: '$error',
          ),
        ),
        error: '$error',
        agentActivity: null,
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<bool> reconnectLastPairing() async {
    _sessionEndedByUser = false;
    _resetAutoReconnect();
    _reportedMcpStartupIssue = false;
    _queuedLaunchPromptSending = false;
    final pairing = _lastPairing;
    if (pairing == null) {
      throw StateError('No recent local pairing saved.');
    }
    final started = DateTime.now();
    _currentSessionId = pairing.sessionId;
    _state = LiveSessionState(
      pairing: pairing,
      status: ConnectionStatus.connecting,
      sessionStartedAt: started,
      activity: [
        _newActivity(
          kind: ActivityKind.connection,
          title: 'Reconnecting',
          detail: 'Opening the trusted session for ${pairing.machineName}.',
          active: true,
        ),
      ],
      agentActivity: 'Reconnecting to ${pairing.agent.label}...',
    );
    notifyListeners();
    try {
      await _relay.connect(pairing);
      _remember(pairing, ConnectionStatus.connecting);
      _persistCurrentHistory();
      return true;
    } catch (error) {
      _state = _state.copyWith(
        status: ConnectionStatus.error,
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Reconnect failed',
            detail: '$error',
          ),
        ),
        error: '$error',
        agentActivity: null,
      );
      notifyListeners();
      _persistCurrentHistory();
      return false;
    }
  }

  Future<void> sendText(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    final id =
        'user-${DateTime.now().microsecondsSinceEpoch}-${_messageCounter++}';
    _pendingPromptId = id;
    _state = _state.copyWith(
      chat: _appendChat(
        _state.chat,
        ChatMessage(
          id: id,
          role: ChatRole.user,
          text: value,
          createdAt: DateTime.now(),
          delivery: ChatDeliveryStatus.sending,
        ),
      ),
      activity: _appendActivity(
        _state.activity,
        _newActivity(
          kind: ActivityKind.thinking,
          title: 'Thinking',
          detail: 'Reading your task and preparing the next action.',
          active: true,
        ),
      ),
      agentActivity: 'Sending...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand(
        'stdin',
        {'text': value.endsWith('\n') ? value : '$value\n'},
      );
      final command = _recordCommand('Sent task to agent', value);
      _state = _state.copyWith(
        chat: _markMessageSent(_state.chat, id),
        activity: _appendActivity(
          _appendActivity(_state.activity, command),
          _newActivity(
            kind: ActivityKind.thinking,
            title: 'Thinking',
            detail: 'Waiting for the local agent stream.',
            active: true,
          ),
        ),
        agentActivity: 'Reading and working...',
        error: null,
      );
      notifyListeners();
      _persistCurrentHistory();
      _watchForMissingReply(id);
    } catch (error) {
      if (_pendingPromptId == id) _pendingPromptId = null;
      _state = _state.copyWith(
        status: ConnectionStatus.error,
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Message failed',
            detail: '$error',
          ),
        ),
        chat: _appendSystemMessage(
          _markMessageFailed(_state.chat, id),
          'Message failed: $error',
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> sendSubmitKey() async {
    if (_state.status != ConnectionStatus.ready) return;
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Sent submit key', 'Pressed Enter in agent terminal.'),
      ),
      agentActivity: 'Sending submit key...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('stdin', {'text': '\n'});
      _state = _state.copyWith(
        agentActivity: 'Waiting for reply...',
      );
      notifyListeners();
      _persistCurrentHistory();
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Submit key failed',
            detail: '$error',
          ),
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> sendTerminalInput(
    String text, {
    bool appendNewline = true,
  }) async {
    final raw = text;
    if (raw.trim().isEmpty) return;
    final payload = appendNewline && !raw.endsWith('\n') ? '$raw\n' : raw;
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Sent terminal input', raw.trim()),
      ),
      agentActivity: 'Sending terminal input...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('stdin', {'text': payload});
      _state = _state.copyWith(
        agentActivity: 'Waiting for terminal output...',
      );
      notifyListeners();
      _persistCurrentHistory();
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Terminal input failed',
            detail: '$error',
          ),
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  void clearTerminalBuffer() {
    _state = _state.copyWith(
      terminal: const [],
      diffs: const [],
      activity: _appendActivity(
        _state.activity,
        _newActivity(
          kind: ActivityKind.command,
          title: 'Cleared terminal view',
          detail: 'Removed local terminal buffer on phone.',
        ),
      ),
    );
    notifyListeners();
    _persistCurrentHistory();
  }

  Future<void> openHistory(String sessionId) async {
    final sessions = await _historyStore.load();
    final matches = sessions.where((item) => item.summary.id == sessionId);
    if (matches.isEmpty) return;
    final stored = matches.first;
    _currentSessionId = stored.summary.id;
    _recentSessions.removeWhere((item) => item.id == stored.summary.id);
    _recentSessions.insert(0, stored.summary);
    final canReconnectToThis = _lastPairing?.sessionId == stored.summary.id;
    _state = LiveSessionState(
      pairing: canReconnectToThis ? _lastPairing : null,
      status: canReconnectToThis
          ? ConnectionStatus.disconnected
          : ConnectionStatus.ended,
      chat: stored.chat,
      activity: stored.activity,
      workspaceRoot: stored.summary.workspaceRoot,
      sessionStartedAt: stored.summary.lastActivity,
      error: null,
    );
    notifyListeners();
  }

  Future<void> interrupt([String? permissionId]) {
    _pushLocalActivity(
      _recordCommand('Interrupted agent', permissionId ?? 'Latest request'),
    );
    return _resolvePermission('interrupt', permissionId);
  }

  Future<void> approve([String? permissionId]) {
    _pushLocalActivity(
      _recordCommand('Approved request', permissionId ?? 'Latest approval'),
    );
    return _resolvePermission('approve', permissionId);
  }

  Future<void> reject([String? permissionId]) {
    _pushLocalActivity(
      _recordCommand('Denied request', permissionId ?? 'Latest approval'),
    );
    return _resolvePermission('reject', permissionId);
  }

  Future<void> requestFiles() async {
    _state = _state.copyWith(
      loadingFiles: true,
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Requested project files', _state.workspaceRoot),
      ),
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('file_list', {});
    } catch (error) {
      _state = _state.copyWith(
        loadingFiles: false,
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Files refresh failed',
            detail: '$error',
          ),
        ),
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> requestWorkspaceTools() async {
    _state = _state.copyWith(
      loadingTools: true,
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Refreshed workspace tools', _state.workspaceRoot),
      ),
      error: null,
    );
    notifyListeners();
    try {
      await _relay.sendCommand('workspace_tools', {});
    } catch (error) {
      _state = _state.copyWith(
        loadingTools: false,
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Tools refresh failed',
            detail: '$error',
          ),
        ),
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> runGitAction(
    String action, {
    String? message,
    String? branch,
  }) async {
    final details = [
      if ((message ?? '').trim().isNotEmpty) 'message=${message!.trim()}',
      if ((branch ?? '').trim().isNotEmpty) 'branch=${branch!.trim()}',
      if (_state.workspaceRoot.trim().isNotEmpty) _state.workspaceRoot.trim(),
    ].join(' | ');
    _state = _state.copyWith(
      gitActionInFlight: action,
      activity: _appendActivity(
        _state.activity,
        _recordCommand(
          'Git ${_gitActionLabel(action)}',
          details.isEmpty ? 'Requested from mobile.' : details,
        ),
      ),
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('git_action', {
        'action': action,
        if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
        if ((branch ?? '').trim().isNotEmpty) 'branch': branch!.trim(),
      });
    } catch (error) {
      _state = _state.copyWith(
        gitActionInFlight: null,
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Git command failed',
            detail: '$error',
          ),
        ),
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> readFile(String path) async {
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Opened file', path),
      ),
      openingFilePath: path,
      agentActivity: 'Opening $path...',
      error: null,
    );
    notifyListeners();
    try {
      await _relay.sendCommand('file_read', {'path': path});
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Open failed',
            detail: '$error',
          ),
        ),
        openingFilePath: null,
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> saveFile(String path, String content) async {
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Saved file', path),
      ),
      agentActivity: 'Saving $path...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('file_write', {
        'path': path,
        'encoding': 'base64',
        'content': base64StdNoPadEncode(utf8.encode(content)),
      });
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Save failed',
            detail: '$error',
          ),
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> deleteFile(String path) async {
    final target = path.trim();
    if (target.isEmpty) return;
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Deleted file', target),
      ),
      agentActivity: 'Deleting $target...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('file_delete', {'path': target});
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Delete failed',
            detail: '$error',
          ),
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> renameFile(String from, String to) async {
    final source = from.trim();
    final target = to.trim();
    if (source.isEmpty || target.isEmpty) return;
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Renamed file', '$source -> $target'),
      ),
      agentActivity: 'Renaming file...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('file_rename', {
        'from': source,
        'to': target,
      });
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Rename failed',
            detail: '$error',
          ),
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> createFolder(String path) async {
    final target = path.trim();
    if (target.isEmpty) return;
    _state = _state.copyWith(
      activity: _appendActivity(
        _state.activity,
        _recordCommand('Created folder', target),
      ),
      agentActivity: 'Creating folder...',
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
    try {
      await _relay.sendCommand('folder_create', {'path': target});
    } catch (error) {
      _state = _state.copyWith(
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'Create folder failed',
            detail: '$error',
          ),
        ),
        agentActivity: null,
        error: '$error',
      );
      notifyListeners();
      _persistCurrentHistory();
    }
  }

  Future<void> switchOpenFile(String path) async {
    final target = path.trim();
    if (target.isEmpty) return;
    final existing = _state.openFiles.where((file) => file.path == target);
    if (existing.isNotEmpty) {
      _state = _state.copyWith(
        openFile: existing.first,
        openingFilePath: null,
        error: null,
      );
      notifyListeners();
      return;
    }
    await readFile(target);
  }

  void closeOpenFile(String path) {
    final target = path.trim();
    if (target.isEmpty || _state.openFiles.isEmpty) return;
    final next = _state.openFiles.where((file) => file.path != target).toList();
    CodeFile? nextActive = _state.openFile;
    if (_state.openFile?.path == target) {
      nextActive = next.isEmpty ? null : next.last;
    }
    _state = _state.copyWith(
      openFiles: next,
      openFile: nextActive,
      error: null,
    );
    notifyListeners();
    _persistCurrentHistory();
  }

  Future<void> end() async {
    _sessionEndedByUser = true;
    _pendingPromptId = null;
    _queuedLaunchPrompt = null;
    _queuedLaunchPromptSending = false;
    _resetAutoReconnect();
    await _relay.close();
    _state = _state.copyWith(
      status: ConnectionStatus.ended,
      gitActionInFlight: null,
      activity: _appendActivity(
        _state.activity,
        _newActivity(
          kind: ActivityKind.complete,
          title: 'Session ended',
          detail: 'Closed the phone connection.',
        ),
      ),
      agentActivity: null,
    );
    notifyListeners();
    _persistCurrentHistory();
  }

  void _handleEvent(RelayEvent event) {
    var shouldFlushLaunchPrompt = false;
    switch (event.type) {
      case 'connecting':
        _state = _state.copyWith(
          status: ConnectionStatus.connecting,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.connection,
              title: 'Connecting',
              detail: 'Opening encrypted relay channel.',
              active: true,
            ),
          ),
          agentActivity: 'Connecting to relay...',
          error: null,
        );
        break;
      case 'session_ready':
        _sessionEndedByUser = false;
        _resetAutoReconnect();
        _state = _state.copyWith(
          status: ConnectionStatus.ready,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.connection,
              title: 'Connected',
              detail: 'Encrypted channel is ready.',
            ),
          ),
          agentActivity: 'Agent connected. Waiting for first output...',
          mcpStartupFailed: false,
          error: null,
        );
        final pairing = _state.pairing;
        if (pairing != null) _remember(pairing, ConnectionStatus.ready);
        break;
      case 'session_started':
        _sessionEndedByUser = false;
        _resetAutoReconnect();
        final cwd = event.data['cwd'] as String? ?? _state.workspaceRoot;
        _state = _state.copyWith(
          status: ConnectionStatus.ready,
          workspaceRoot: cwd,
          sessionStartedAt: _state.sessionStartedAt ?? DateTime.now(),
          chat: _appendSystemMessage(
            _state.chat,
            cwd.isEmpty
                ? 'Connected. Send a task to start.'
                : 'Connected to $cwd.',
          ),
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.connection,
              title: 'Workspace ready',
              detail: cwd.isEmpty ? 'Agent session started.' : cwd,
            ),
          ),
          agentActivity: null,
          mcpStartupFailed: false,
          error: null,
        );
        final pairing = _state.pairing;
        if (pairing != null) {
          _remember(pairing, ConnectionStatus.ready, workspaceRoot: cwd);
        }
        unawaited(requestFiles());
        shouldFlushLaunchPrompt = true;
        break;
      case 'disconnect':
        if (_sessionEndedByUser) {
          _state = _state.copyWith(
            status: ConnectionStatus.ended,
            gitActionInFlight: null,
            mcpStartupFailed: false,
            error: null,
            agentActivity: null,
          );
          break;
        }
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.disconnected,
            loadingFiles: false,
            error: event.data['error'] as String?,
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.error,
                title: 'Disconnected',
                detail: event.data['error'] as String? ??
                    'Relay socket disconnected.',
              ),
            ),
            gitActionInFlight: null,
            mcpStartupFailed: false,
            agentActivity: null,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        _scheduleAutoReconnect();
        break;
      case 'permission_requested':
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.ready,
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.review,
                title: 'Approval needed',
                detail: event.data['detail'] as String? ??
                    'The agent needs your decision.',
                active: true,
              ),
            ),
            agentActivity: 'Waiting for your approval...',
            error: null,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'permission_resolved':
        _state = _state.copyWith(
          inbox: _withoutResolvedPermission(
            _state.inbox,
            event.data['id'] as String?,
          ),
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.review,
              title: 'Approval resolved',
              detail: event.data['action'] as String? ?? 'Decision sent.',
            ),
          ),
        );
        break;
      case 'diff_ready':
        final patch = _decodeEventText(event.data, 'patch');
        final model = DiffCardModel(
          filePath: event.data['file_path'] as String? ?? 'Working tree',
          summary: event.data['summary'] as String? ?? 'Changes ready',
          patch: patch.isEmpty ? 'Diff unavailable.' : patch,
        );
        _state = _pushInbox(
          _state.copyWith(
            diffs: _upsertDiff(_state.diffs, model),
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.file,
                title: 'Changes detected',
                detail: model.summary,
              ),
            ),
            agentActivity: null,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'process_exit':
        _sessionEndedByUser = true;
        _resetAutoReconnect();
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.ended,
            loadingFiles: false,
            gitActionInFlight: null,
            chat: _appendSystemMessage(_state.chat, 'Session ended.'),
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.complete,
                title: 'Agent finished',
                detail: (event.data['error'] as String?)?.isNotEmpty == true
                    ? event.data['error'] as String
                    : 'The local session ended.',
              ),
            ),
            agentActivity: null,
            mcpStartupFailed: false,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'pairing_expired':
        _sessionEndedByUser = false;
        _resetAutoReconnect();
        _lastPairing = null;
        unawaited(_pairingStore.clearLastPairing());
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.error,
            loadingFiles: false,
            gitActionInFlight: null,
            error: event.data['message'] as String?,
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.error,
                title: 'Pairing expired',
                detail: event.data['message'] as String? ??
                    'Start a new local session and scan again.',
              ),
            ),
            agentActivity: null,
            mcpStartupFailed: false,
          ),
          AttentionItem.fromEvent(type: 'error', data: event.data),
        );
        break;
      case 'terminal_output':
        final text = _cleanTerminalText(utf8.decode(
          base64StdNoPadDecode(event.data['data'] as String? ?? ''),
          allowMalformed: true,
        ));
        if (text.isEmpty) break;
        final next = [
          ..._state.terminal,
          TerminalChunk(text: text, createdAt: DateTime.now()),
        ];
        final mcpStartupIssue = _hasMcpStartupIssue(text);
        final mcpStartupFailed = _state.mcpStartupFailed || mcpStartupIssue;
        final agentOutput = _chatSafeOutput(text);
        if (agentOutput.isNotEmpty || mcpStartupIssue) {
          _pendingPromptId = null;
        }
        final chat = mcpStartupIssue
            ? _appendSystemMessage(
                _state.chat,
                'Codex MCP startup failed. The terminal is live, but Codex may not answer until that MCP server is fixed or disabled.',
              )
            : _appendAgentOutput(_state.chat, agentOutput);
        final activity = mcpStartupIssue && !_reportedMcpStartupIssue
            ? _appendActivity(
                _appendTerminalActivity(_state.activity, text),
                _newActivity(
                  kind: ActivityKind.error,
                  title: 'MCP startup failed',
                  detail:
                      'codex_apps did not start. Raw details are in Terminal.',
                ),
              )
            : _appendTerminalActivity(_state.activity, text);
        if (mcpStartupIssue) _reportedMcpStartupIssue = true;
        _state = _state.copyWith(
          terminal: next.length > 600 ? next.sublist(next.length - 600) : next,
          diffs: _extractDiffs(next),
          chat: chat,
          activity: activity,
          mcpStartupFailed: mcpStartupFailed,
          agentActivity: null,
          error: null,
        );
        break;
      case 'file_snapshot':
        final rows = event.data['files'];
        final root = event.data['root'] as String? ?? _state.workspaceRoot;
        if (rows is List) {
          _state = _state.copyWith(
            files: rows
                .whereType<Map>()
                .map((e) => FileEntry.fromJson(e.cast<String, dynamic>()))
                .toList(),
            loadingFiles: false,
            workspaceRoot: root,
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.file,
                title: 'Read project files',
                detail:
                    '${rows.length} files visible in ${root.isEmpty ? 'workspace' : root}.',
              ),
            ),
          );
          final pairing = _state.pairing;
          if (pairing != null) {
            _remember(pairing, _state.status, workspaceRoot: root);
          }
        }
        break;
      case 'workspace_tools':
        _state = _state.copyWith(
          tools: WorkspaceToolsSnapshot.fromJson(event.data),
          loadingTools: false,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.command,
              title: 'Workspace tools ready',
              detail:
                  '${(event.data['ports'] as List?)?.length ?? 0} ports scanned.',
            ),
          ),
          error: null,
        );
        break;
      case 'git_action_result':
        final ok = event.data['ok'] as bool? ?? false;
        final action = event.data['action'] as String? ?? 'action';
        final summary = (event.data['summary'] as String?)?.trim();
        final output = (event.data['output'] as String?)?.trim() ?? '';
        final display = summary?.isNotEmpty == true
            ? summary!
            : ok
                ? 'Git ${_gitActionLabel(action)} complete.'
                : 'Git ${_gitActionLabel(action)} failed.';
        final detail = output.isEmpty ? display : '$display\n$output';
        _state = _state.copyWith(
          gitActionInFlight: null,
          chat: _appendSystemMessage(_state.chat, detail),
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ok ? ActivityKind.command : ActivityKind.error,
              title: ok ? 'Git command complete' : 'Git command failed',
              detail: display,
            ),
          ),
          error: ok ? null : display,
        );
        break;
      case 'file_content':
        final path = event.data['path'] as String? ?? 'untitled';
        final content = utf8.decode(
          base64StdNoPadDecode(event.data['content'] as String? ?? ''),
          allowMalformed: true,
        );
        final file = CodeFile(path: path, content: content);
        final openFiles = [
          ..._state.openFiles.where((item) => item.path != path),
          file,
        ];
        _state = _state.copyWith(
          openFile: file,
          openFiles: openFiles.length > 8
              ? openFiles.sublist(openFiles.length - 8)
              : openFiles,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.file,
              title: 'File loaded',
              detail: path,
            ),
          ),
          openingFilePath: null,
          agentActivity: null,
          error: null,
        );
        break;
      case 'file_saved':
        final path = event.data['path'] as String? ?? 'file';
        final updatedOpenFiles = _state.openFiles
            .map((item) => item.path == path
                ? CodeFile(
                    path: item.path,
                    content: _state.openFile?.content ?? item.content)
                : item)
            .toList();
        _state = _state.copyWith(
          chat: _appendSystemMessage(_state.chat, 'Saved $path.'),
          openFiles: updatedOpenFiles,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.file,
              title: 'File saved',
              detail: path,
            ),
          ),
          agentActivity: null,
          error: null,
        );
        unawaited(requestFiles());
        break;
      case 'file_deleted':
        final path = event.data['path'] as String? ?? 'file';
        final nextOpenFiles =
            _state.openFiles.where((item) => item.path != path).toList();
        final nextOpen = _state.openFile?.path == path
            ? (nextOpenFiles.isEmpty ? null : nextOpenFiles.last)
            : _state.openFile;
        _state = _state.copyWith(
          chat: _appendSystemMessage(_state.chat, 'Deleted $path.'),
          openFiles: nextOpenFiles,
          openFile: nextOpen,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.file,
              title: 'File deleted',
              detail: path,
            ),
          ),
          agentActivity: null,
          error: null,
        );
        unawaited(requestFiles());
        break;
      case 'file_renamed':
        final from = event.data['from'] as String? ?? '';
        final to = event.data['to'] as String? ?? '';
        final nextOpenFiles = _state.openFiles
            .map((item) => item.path == from
                ? CodeFile(path: to, content: item.content)
                : item)
            .toList();
        final nextOpen = _state.openFile?.path == from
            ? CodeFile(path: to, content: _state.openFile!.content)
            : _state.openFile;
        _state = _state.copyWith(
          chat: _appendSystemMessage(
            _state.chat,
            'Renamed ${from.isEmpty ? 'file' : from} to $to.',
          ),
          openFiles: nextOpenFiles,
          openFile: nextOpen,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.file,
              title: 'File renamed',
              detail: '$from -> $to',
            ),
          ),
          agentActivity: null,
          error: null,
        );
        unawaited(requestFiles());
        break;
      case 'folder_created':
        final path = event.data['path'] as String? ?? '';
        _state = _state.copyWith(
          chat: _appendSystemMessage(_state.chat, 'Created folder $path.'),
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.file,
              title: 'Folder created',
              detail: path,
            ),
          ),
          agentActivity: null,
          error: null,
        );
        unawaited(requestFiles());
        break;
      case 'error':
        if (_sessionEndedByUser) {
          break;
        }
        _resetAutoReconnect();
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.error,
            loadingFiles: false,
            gitActionInFlight: null,
            error: event.data['message'] as String?,
            chat: _appendSystemMessage(
              _state.chat,
              event.data['message'] as String? ?? 'Session error.',
            ),
            activity: _appendActivity(
              _state.activity,
              _newActivity(
                kind: ActivityKind.error,
                title: 'Session error',
                detail: event.data['message'] as String? ??
                    'The local session failed.',
              ),
            ),
            agentActivity: null,
            mcpStartupFailed: false,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
    }
    notifyListeners();
    _persistCurrentHistory();
    if (shouldFlushLaunchPrompt) {
      unawaited(_sendQueuedLaunchPrompt());
    }
  }

  Future<void> _sendQueuedLaunchPrompt() async {
    if (_queuedLaunchPromptSending || _state.status != ConnectionStatus.ready) {
      return;
    }
    final prompt = _queuedLaunchPrompt?.trim();
    if (prompt == null || prompt.isEmpty) return;
    _queuedLaunchPrompt = null;
    _queuedLaunchPromptSending = true;
    try {
      await sendText(prompt);
    } finally {
      _queuedLaunchPromptSending = false;
    }
  }

  String _cleanTerminalText(String text) {
    var next = text
        .replaceAll(RegExp(r'\x1B\][^\x07]*(?:\x07|\x1B\\)'), '')
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'\x1B[@-Z\\-_]'), '');
    next = next.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return next.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  }

  List<DiffCardModel> _extractDiffs(List<TerminalChunk> chunks) {
    final joined = chunks.map((e) => e.text).join();
    final marker = 'diff --git ';
    if (!joined.contains(marker)) return _state.diffs;
    final sections = joined.split(marker).skip(1).take(4);
    return sections.map((section) {
      final firstLine = section.split('\n').first;
      final file = firstLine.split(' ').last.replaceFirst('b/', '');
      return DiffCardModel(
        filePath: file,
        summary: 'Changes detected in $file',
        patch: '$marker$section',
      );
    }).toList();
  }

  void _remember(
    PairingPayload pairing,
    ConnectionStatus status, {
    String? workspaceRoot,
  }) {
    _currentSessionId = pairing.sessionId;
    final existing = _summaryForId(pairing.sessionId);
    _recentSessions.removeWhere((s) => s.id == pairing.sessionId);
    _recentSessions.insert(
      0,
      SessionSummary(
        id: pairing.sessionId,
        agent: pairing.agent,
        mode: pairing.mode,
        status: status,
        lastActivity: DateTime.now(),
        machineName: pairing.machineName,
        machineOs: pairing.machineOs,
        workspaceRoot: workspaceRoot ?? _state.workspaceRoot,
        title: _titleForCurrentState(existing?.title),
      ),
    );
  }

  Future<void> _restoreLastPairing() async {
    final pairing = await _pairingStore.loadLastPairing();
    if (pairing == null) return;
    _lastPairing = pairing;
    if (!pairing.isExpired) {
      _remember(pairing, ConnectionStatus.disconnected);
    }
    notifyListeners();
  }

  Future<void> _restoreHistory() async {
    final sessions = await _historyStore.load();
    for (final stored in sessions.reversed) {
      _recentSessions.removeWhere((item) => item.id == stored.summary.id);
      _recentSessions.insert(0, stored.summary);
    }
    notifyListeners();
  }

  String _decodeEventText(Map<String, dynamic> data, String key) {
    final value = data[key] as String? ?? '';
    if (value.isEmpty) return '';
    if (data['encoding'] == 'base64') {
      return utf8.decode(base64StdNoPadDecode(value), allowMalformed: true);
    }
    return value;
  }

  LiveSessionState _pushInbox(LiveSessionState state, AttentionItem item) {
    unawaited(_notifications.showAttention(item));
    final next = [
      item,
      ...state.inbox.where((existing) => existing.id != item.id),
    ];
    return state.copyWith(
      inbox: next.length > 40 ? next.sublist(0, 40) : next,
    );
  }

  Future<void> _resolvePermission(String action, String? permissionId) {
    final payload = <String, dynamic>{};
    if (permissionId != null && permissionId.isNotEmpty) {
      payload['id'] = permissionId;
    }
    return _relay.sendCommand(action, payload);
  }

  List<AttentionItem> _withoutResolvedPermission(
    List<AttentionItem> inbox,
    String? permissionId,
  ) {
    if (permissionId != null && permissionId.isNotEmpty) {
      return inbox.where((item) => item.id != permissionId).toList();
    }
    var removedFallback = false;
    final next = <AttentionItem>[];
    for (final item in inbox) {
      if (!removedFallback && item.kind == AttentionKind.permission) {
        removedFallback = true;
        continue;
      }
      next.add(item);
    }
    return next;
  }

  List<DiffCardModel> _upsertDiff(
    List<DiffCardModel> current,
    DiffCardModel model,
  ) {
    return [
      model,
      ...current.where((item) => item.filePath != model.filePath),
    ].take(12).toList();
  }

  ActivityEntry _newActivity({
    required ActivityKind kind,
    required String title,
    required String detail,
    int? commandCount,
    bool active = false,
  }) {
    return ActivityEntry(
      id: 'activity-${DateTime.now().microsecondsSinceEpoch}-${_activityCounter++}',
      kind: kind,
      title: title,
      detail: detail,
      createdAt: DateTime.now(),
      commandCount: commandCount,
      active: active,
    );
  }

  ActivityEntry _recordCommand(String title, String detail) {
    _commandCounter++;
    return _newActivity(
      kind: ActivityKind.command,
      title: title,
      detail: detail.trim().isEmpty ? 'Mobile command sent.' : detail.trim(),
      commandCount: _commandCounter,
    );
  }

  void _pushLocalActivity(ActivityEntry entry) {
    _state = _state.copyWith(
      activity: _appendActivity(_state.activity, entry),
    );
    notifyListeners();
    _persistCurrentHistory();
  }

  List<ActivityEntry> _appendActivity(
    List<ActivityEntry> current,
    ActivityEntry entry,
  ) {
    if (current.isNotEmpty &&
        current.last.title == entry.title &&
        current.last.detail == entry.detail) {
      return current;
    }
    final settled = current
        .map((item) => item.active ? item.copyWith(active: false) : item)
        .toList();
    final next = [...settled, entry];
    return next.length > 80 ? next.sublist(next.length - 80) : next;
  }

  List<ActivityEntry> _appendTerminalActivity(
    List<ActivityEntry> current,
    String text,
  ) {
    final summary = _terminalSummary(text);
    if (summary.isEmpty) return current;
    if (current.isNotEmpty &&
        current.last.active &&
        current.last.kind == ActivityKind.thinking) {
      return [
        ...current.take(current.length - 1),
        current.last.copyWith(detail: summary, active: false),
      ];
    }
    if (current.isNotEmpty &&
        current.last.kind == ActivityKind.thinking &&
        current.last.detail == summary) {
      return current;
    }
    return _appendActivity(
      current,
      _newActivity(
        kind: ActivityKind.thinking,
        title: 'Thinking',
        detail: summary,
      ),
    );
  }

  String _terminalSummary(String text) {
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) =>
            line.isNotEmpty &&
            !_isCodexPromptUiLine(line) &&
            !line.contains('Pairing URI:') &&
            !line.contains('QR image:') &&
            !line.startsWith('Session:') &&
            !line.startsWith('Machine:'))
        .toList();
    if (lines.isEmpty) return '';
    final summary = lines.take(5).join('\n');
    const limit = 420;
    if (summary.length <= limit) return summary;
    return '${summary.substring(0, limit)}...';
  }

  List<ChatMessage> _appendChat(
    List<ChatMessage> current,
    ChatMessage message,
  ) {
    final next = [...current, message];
    return next.length > 120 ? next.sublist(next.length - 120) : next;
  }

  List<ChatMessage> _appendSystemMessage(
    List<ChatMessage> current,
    String text,
  ) {
    final value = text.trim();
    if (value.isEmpty) return current;
    if (current.isNotEmpty &&
        current.last.role == ChatRole.system &&
        current.last.text == value) {
      return current;
    }
    return _appendChat(
      current,
      ChatMessage(
        id: 'system-${DateTime.now().microsecondsSinceEpoch}-${_messageCounter++}',
        role: ChatRole.system,
        text: value,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<ChatMessage> _appendAgentOutput(
    List<ChatMessage> current,
    String text,
  ) {
    final value = _chatSafeOutput(text);
    if (value.isEmpty) return current;
    if (current.isNotEmpty && current.last.role == ChatRole.agent) {
      final last = current.last;
      final mergedText =
          '${last.text}${last.text.endsWith('\n') ? '' : '\n'}$value';
      return [
        ...current.take(current.length - 1),
        last.copyWith(text: _capMessageText(mergedText)),
      ];
    }
    return _appendChat(
      current,
      ChatMessage(
        id: 'agent-${DateTime.now().microsecondsSinceEpoch}-${_messageCounter++}',
        role: ChatRole.agent,
        text: value,
        createdAt: DateTime.now(),
      ),
    );
  }

  List<ChatMessage> _markMessageSent(List<ChatMessage> current, String id) {
    return current
        .map((message) => message.id == id
            ? message.copyWith(delivery: ChatDeliveryStatus.sent)
            : message)
        .toList();
  }

  List<ChatMessage> _markMessageFailed(List<ChatMessage> current, String id) {
    return current
        .map((message) => message.id == id
            ? message.copyWith(delivery: ChatDeliveryStatus.failed)
            : message)
        .toList();
  }

  String _chatSafeOutput(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final withoutQrNoise = trimmed
        .split('\n')
        .map((line) => line.trim())
        .where((line) =>
            line.isNotEmpty &&
            !_isCodexPromptUiLine(line) &&
            !_hasMcpStartupIssue(line) &&
            !line.contains('Pairing URI:') &&
            !line.contains('QR image:'))
        .join('\n')
        .trim();
    return _capMessageText(withoutQrNoise);
  }

  void _watchForMissingReply(String promptId) {
    Future<void>.delayed(const Duration(seconds: 12), () {
      if (_pendingPromptId != promptId ||
          _state.status != ConnectionStatus.ready) {
        return;
      }
      _state = _state.copyWith(
        chat: _appendSystemMessage(
          _state.chat,
          _reportedMcpStartupIssue
              ? 'No reply yet. Codex reported an MCP startup warning. Check Terminal and keep Reliable mode on.'
              : 'No reply yet. Check Terminal for pending prompt/approval, then retry.',
        ),
        activity: _appendActivity(
          _state.activity,
          _newActivity(
            kind: ActivityKind.error,
            title: 'No agent reply',
            detail:
                'The message was sent, but no usable Codex output arrived after 12 seconds.',
          ),
        ),
        agentActivity: null,
      );
      _persistCurrentHistory();
      notifyListeners();
    });
  }

  void _scheduleAutoReconnect() {
    if (_sessionEndedByUser) return;
    final pairing = _state.pairing ?? _lastPairing;
    if (pairing == null) return;
    if (_state.status != ConnectionStatus.disconnected) return;
    if (_autoReconnectTimer != null) return;
    if (_autoReconnectAttempt >= 4) {
      _state = _state.copyWith(
        chat: _appendSystemMessage(
          _state.chat,
          'Auto reconnect failed. Start a new local session from desktop.',
        ),
        agentActivity: null,
      );
      notifyListeners();
      _persistCurrentHistory();
      return;
    }

    const delays = [1, 2, 4, 8];
    final seconds = delays[_autoReconnectAttempt];
    _state = _state.copyWith(agentActivity: 'Reconnecting in ${seconds}s...');
    notifyListeners();
    _persistCurrentHistory();
    _autoReconnectTimer = Timer(Duration(seconds: seconds), () async {
      _autoReconnectTimer = null;
      if (_state.status != ConnectionStatus.disconnected) return;
      _autoReconnectAttempt++;
      _state = _state.copyWith(
        status: ConnectionStatus.connecting,
        agentActivity: 'Reconnecting to relay...',
      );
      notifyListeners();
      _persistCurrentHistory();
      try {
        await _relay.connect(pairing);
        _remember(
          pairing,
          ConnectionStatus.connecting,
          workspaceRoot: _state.workspaceRoot,
        );
      } catch (error) {
        _state = _state.copyWith(
          status: ConnectionStatus.disconnected,
          activity: _appendActivity(
            _state.activity,
            _newActivity(
              kind: ActivityKind.error,
              title: 'Reconnect attempt failed',
              detail: '$error',
            ),
          ),
          error: '$error',
          agentActivity: null,
        );
        notifyListeners();
        _persistCurrentHistory();
        _scheduleAutoReconnect();
      }
    });
  }

  void _resetAutoReconnect() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = null;
    _autoReconnectAttempt = 0;
  }

  bool _hasMcpStartupIssue(String text) {
    return text.contains('MCP startup incomplete') ||
        text.contains('MCP client for `codex_apps` failed') ||
        text.contains('codex_apps') && text.contains('MCP startup failed');
  }

  bool _isCodexPromptUiLine(String line) {
    final value = line.trim();
    if (value.isEmpty) return true;
    if (value.startsWith('>') || value.startsWith('\u203a')) return true;
    if (RegExp(r'^gpt-[\w.\-]+(?:\s+[\w.\-]+)*\s*[\u00b7.]?$')
        .hasMatch(value)) {
      return true;
    }
    if (RegExp(r'^[~A-Za-z]:?\\.*').hasMatch(value)) return true;
    if (RegExp(r'^~[/\\].*').hasMatch(value)) return true;
    if (value == 'esc to interrupt' || value.endsWith('esc to interrupt)')) {
      return true;
    }
    return false;
  }

  String _capMessageText(String text) {
    const limit = 6000;
    if (text.length <= limit) return text;
    return text.substring(text.length - limit);
  }

  void _persistCurrentHistory() {
    final sessionId = _currentSessionId ?? _state.pairing?.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    if (_state.chat.isEmpty && _state.activity.isEmpty) return;
    final summary = _summaryForCurrentSession(sessionId);
    _recentSessions.removeWhere((item) => item.id == summary.id);
    _recentSessions.insert(0, summary);
    unawaited(
      _historyStore.save(
        StoredChatSession(
          summary: summary,
          chat: _state.chat,
          activity: _state.activity,
        ),
      ),
    );
  }

  SessionSummary _summaryForCurrentSession(String sessionId) {
    final pairing = _state.pairing;
    final existing = _summaryForId(sessionId);
    return SessionSummary(
      id: sessionId,
      agent: pairing?.agent ?? existing?.agent ?? AgentKind.codex,
      mode: pairing?.mode ?? existing?.mode ?? 'local',
      status: _state.status,
      lastActivity: DateTime.now(),
      machineName:
          pairing?.machineName ?? existing?.machineName ?? 'Local machine',
      machineOs: pairing?.machineOs ?? existing?.machineOs ?? '',
      workspaceRoot: _state.workspaceRoot.isNotEmpty
          ? _state.workspaceRoot
          : existing?.workspaceRoot ?? '',
      title: _titleForCurrentState(existing?.title),
    );
  }

  SessionSummary? _summaryForId(String id) {
    for (final summary in _recentSessions) {
      if (summary.id == id) return summary;
    }
    return null;
  }

  String _titleForCurrentState(String? fallback) {
    for (final message in _state.chat) {
      if (message.role == ChatRole.user && message.text.trim().isNotEmpty) {
        return _shortTitle(message.text);
      }
    }
    if (fallback != null && fallback.trim().isNotEmpty) {
      return fallback.trim();
    }
    final root = _state.workspaceRoot.trim().replaceAll('\\', '/');
    if (root.isNotEmpty) {
      final parts = root.split('/').where((part) => part.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last;
    }
    return _state.pairing?.agent.label ?? 'New chat';
  }

  String _shortTitle(String text) {
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 54) return collapsed;
    return '${collapsed.substring(0, 54)}...';
  }

  String _gitActionLabel(String action) {
    return switch (action.trim().toLowerCase()) {
      'stage_all' => 'stage all',
      'unstage_all' => 'unstage all',
      'commit' => 'commit',
      'push' => 'push',
      'pull' => 'pull',
      'checkout' => 'checkout',
      _ => action.trim().isEmpty ? 'action' : action.trim(),
    };
  }

  @override
  void dispose() {
    _resetAutoReconnect();
    _relaySub?.cancel();
    _relay.close();
    super.dispose();
  }
}
