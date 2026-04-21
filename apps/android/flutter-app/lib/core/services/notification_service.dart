import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:codex_nomad/models/session_models.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {
      // Firebase is optional until google-services.json is added.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    try {
      await _local.initialize(settings: settings);
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {
      // Local notifications are best-effort outside a packaged mobile app.
    }
    _initialized = true;
  }

  Future<void> showAttention(AttentionItem item) async {
    await initialize();
    if (!_shouldNotify(item.kind)) return;
    const android = AndroidNotificationDetails(
      'agent_attention',
      'Agent attention',
      channelDescription: 'Local coding agent approvals and review alerts',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.private,
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    try {
      await _local.show(
        id: item.id.hashCode & 0x7fffffff,
        title: item.title,
        body: _safeBody(item),
        notificationDetails:
            const NotificationDetails(android: android, iOS: ios),
        payload: item.id,
      );
    } catch (_) {
      // The inbox still updates even if the platform notification bridge fails.
    }
  }

  bool _shouldNotify(AttentionKind kind) {
    return switch (kind) {
      AttentionKind.permission ||
      AttentionKind.diff ||
      AttentionKind.blocked ||
      AttentionKind.connection ||
      AttentionKind.error =>
        true,
      AttentionKind.complete => false,
    };
  }

  String _safeBody(AttentionItem item) {
    return switch (item.kind) {
      AttentionKind.permission => 'A local agent needs approval.',
      AttentionKind.diff => 'A local agent has changes ready to review.',
      AttentionKind.connection => 'A local agent connection changed.',
      AttentionKind.error => 'A local agent hit an error.',
      AttentionKind.blocked => 'A local agent is blocked.',
      AttentionKind.complete => 'A local agent finished.',
    };
  }
}
