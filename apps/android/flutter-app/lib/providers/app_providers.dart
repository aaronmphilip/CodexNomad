import 'dart:async';
import 'dart:convert';

import 'package:codex_nomad/core/config/app_config.dart';
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
    unawaited(_restoreLastPairing());
  }

  final RelayService _relay;
  final NotificationService _notifications;
  final LocalPairingStore _pairingStore = LocalPairingStore();
  StreamSubscription<RelayEvent>? _relaySub;
  LiveSessionState _state = const LiveSessionState();
  final List<SessionSummary> _recentSessions = [];
  PairingPayload? _lastPairing;

  LiveSessionState get state => _state;
  List<SessionSummary> get recentSessions => List.unmodifiable(_recentSessions);
  PairingPayload? get lastPairing => _lastPairing;

  Future<void> connectFromQr(String rawQr) async {
    final pairing = PairingPayload.fromQr(rawQr);
    _state = LiveSessionState(
      pairing: pairing,
      status: ConnectionStatus.connecting,
    );
    notifyListeners();
    try {
      await _relay.connect(pairing);
      _lastPairing = pairing;
      unawaited(_pairingStore.saveLastPairing(pairing));
      _remember(pairing, ConnectionStatus.connecting);
    } catch (error) {
      _state = _state.copyWith(
        status: ConnectionStatus.error,
        error: '$error',
      );
      notifyListeners();
    }
  }

  Future<bool> reconnectLastPairing() async {
    final pairing = _lastPairing;
    if (pairing == null) {
      throw StateError('No recent local pairing saved.');
    }
    _state = LiveSessionState(
      pairing: pairing,
      status: ConnectionStatus.connecting,
    );
    notifyListeners();
    try {
      await _relay.connect(pairing);
      _remember(pairing, ConnectionStatus.connecting);
      return true;
    } catch (error) {
      _state = _state.copyWith(
        status: ConnectionStatus.error,
        error: '$error',
      );
      notifyListeners();
      return false;
    }
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    await _relay
        .sendCommand('stdin', {'text': text.endsWith('\n') ? text : '$text\n'});
  }

  Future<void> interrupt([String? permissionId]) {
    return _resolvePermission('interrupt', permissionId);
  }

  Future<void> approve([String? permissionId]) {
    return _resolvePermission('approve', permissionId);
  }

  Future<void> reject([String? permissionId]) {
    return _resolvePermission('reject', permissionId);
  }

  Future<void> requestFiles() => _relay.sendCommand('file_list', {});

  Future<void> readFile(String path) {
    return _relay.sendCommand('file_read', {'path': path});
  }

  Future<void> saveFile(String path, String content) {
    return _relay.sendCommand('file_write', {
      'path': path,
      'encoding': 'base64',
      'content': base64StdNoPadEncode(utf8.encode(content)),
    });
  }

  Future<void> end() async {
    await _relay.close();
    _state = _state.copyWith(status: ConnectionStatus.ended);
    notifyListeners();
  }

  void _handleEvent(RelayEvent event) {
    switch (event.type) {
      case 'connecting':
        _state = _state.copyWith(
          status: ConnectionStatus.connecting,
          error: event.data['url'] as String?,
        );
        break;
      case 'session_ready':
        _state = _state.copyWith(status: ConnectionStatus.ready);
        final pairing = _state.pairing;
        if (pairing != null) _remember(pairing, ConnectionStatus.ready);
        break;
      case 'session_started':
        final pairing = _state.pairing;
        if (pairing != null) _remember(pairing, ConnectionStatus.ready);
        break;
      case 'disconnect':
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.disconnected,
            error: event.data['error'] as String?,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'permission_requested':
        _state = _pushInbox(
          _state.copyWith(status: ConnectionStatus.ready),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'permission_resolved':
        _state = _state.copyWith(
          inbox: _withoutResolvedPermission(
            _state.inbox,
            event.data['id'] as String?,
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
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'process_exit':
        _state = _pushInbox(
          _state.copyWith(status: ConnectionStatus.ended),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
      case 'pairing_expired':
        _lastPairing = null;
        unawaited(_pairingStore.clearLastPairing());
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.error,
            error: event.data['message'] as String?,
          ),
          AttentionItem.fromEvent(type: 'error', data: event.data),
        );
        break;
      case 'terminal_output':
        final text = utf8.decode(
          base64StdNoPadDecode(event.data['data'] as String? ?? ''),
          allowMalformed: true,
        );
        final next = [
          ..._state.terminal,
          TerminalChunk(text: text, createdAt: DateTime.now()),
        ];
        _state = _state.copyWith(
          terminal: next.length > 600 ? next.sublist(next.length - 600) : next,
          diffs: _extractDiffs(next),
        );
        break;
      case 'file_snapshot':
        final rows = event.data['files'];
        if (rows is List) {
          _state = _state.copyWith(
            files: rows
                .whereType<Map>()
                .map((e) => FileEntry.fromJson(e.cast<String, dynamic>()))
                .toList(),
          );
        }
        break;
      case 'file_content':
        final path = event.data['path'] as String? ?? 'untitled';
        final content = utf8.decode(
          base64StdNoPadDecode(event.data['content'] as String? ?? ''),
          allowMalformed: true,
        );
        _state =
            _state.copyWith(openFile: CodeFile(path: path, content: content));
        break;
      case 'file_saved':
        requestFiles();
        break;
      case 'error':
        _state = _pushInbox(
          _state.copyWith(
            status: ConnectionStatus.error,
            error: event.data['message'] as String?,
          ),
          AttentionItem.fromEvent(type: event.type, data: event.data),
        );
        break;
    }
    notifyListeners();
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

  void _remember(PairingPayload pairing, ConnectionStatus status) {
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

  @override
  void dispose() {
    _relaySub?.cancel();
    _relay.close();
    super.dispose();
  }
}
