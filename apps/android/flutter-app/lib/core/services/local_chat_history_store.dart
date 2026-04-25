import 'dart:convert';

import 'package:codex_nomad/models/session_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalChatHistoryStore {
  static const _historyKey = 'codex_nomad.chat_history.v1';
  static const _maxSessions = 80;
  static const _maxMessagesPerSession = 160;
  static const _maxActivityPerSession = 120;

  Future<List<StoredChatSession>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => StoredChatSession.fromJson(row.cast<String, dynamic>()))
          .where((session) => session.summary.id.isNotEmpty)
          .toList();
    } catch (_) {
      await prefs.remove(_historyKey);
      return const [];
    }
  }

  Future<void> save(StoredChatSession session) async {
    final current = await load();
    final next = <StoredChatSession>[
      _trim(session),
      ...current.where((item) => item.summary.id != session.summary.id),
    ].take(_maxSessions).toList();
    await _write(next);
  }

  Future<void> replaceAll(List<StoredChatSession> sessions) {
    return _write(sessions.take(_maxSessions).map(_trim).toList());
  }

  Future<void> _write(List<StoredChatSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
    );
  }

  StoredChatSession _trim(StoredChatSession session) {
    final chat = session.chat.length > _maxMessagesPerSession
        ? session.chat.sublist(session.chat.length - _maxMessagesPerSession)
        : session.chat;
    final activity = session.activity.length > _maxActivityPerSession
        ? session.activity
            .sublist(session.activity.length - _maxActivityPerSession)
        : session.activity;
    return StoredChatSession(
      summary: session.summary,
      chat: chat,
      activity: activity,
    );
  }
}
