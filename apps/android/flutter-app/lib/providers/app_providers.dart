import 'dart:async';
import 'dart:convert';

import 'package:codex_nomad/core/config/app_config.dart';
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

final authControllerProvider = ChangeNotifierProvider<AuthController>((ref) {
  return AuthController(ref.watch(supabaseServiceProvider));
});

final sessionControllerProvider =
    ChangeNotifierProvider<SessionController>((ref) {
  final controller = SessionController(ref.watch(appConfigProvider));
  ref.onDispose(controller.dispose);
  return controller;
});

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
  SessionController(AppConfig config) : _relay = RelayService(config) {
    _relaySub = _relay.events.listen(_handleEvent);
  }

  final RelayService _relay;
  StreamSubscription<RelayEvent>? _relaySub;
  LiveSessionState _state = const LiveSessionState();
  final List<SessionSummary> _recentSessions = [];

  LiveSessionState get state => _state;
  List<SessionSummary> get recentSessions => List.unmodifiable(_recentSessions);

  Future<void> connectFromQr(String rawQr) async {
    final pairing = PairingPayload.fromQr(rawQr);
    _state = LiveSessionState(
      pairing: pairing,
      status: ConnectionStatus.connecting,
    );
    notifyListeners();
    try {
      await _relay.connect(pairing);
      _remember(pairing, ConnectionStatus.connecting);
    } catch (error) {
      _state = _state.copyWith(
        status: ConnectionStatus.error,
        error: '$error',
      );
      notifyListeners();
    }
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    await _relay
        .sendCommand('stdin', {'text': text.endsWith('\n') ? text : '$text\n'});
  }

  Future<void> interrupt() => _relay.sendCommand('interrupt', {});
  Future<void> approve() => _relay.sendCommand('approve', {});
  Future<void> reject() => _relay.sendCommand('reject', {});
  Future<void> approveAll() => _relay.sendCommand('stdin', {'text': 'y\n'});
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
      case 'disconnect':
        _state = _state.copyWith(
          status: ConnectionStatus.disconnected,
          error: event.data['error'] as String?,
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
        _state = _state.copyWith(
          status: ConnectionStatus.error,
          error: event.data['message'] as String?,
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
      ),
    );
  }

  @override
  void dispose() {
    _relaySub?.cancel();
    _relay.close();
    super.dispose();
  }
}
