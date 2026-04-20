import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  Future<void> initialize() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {
      // Firebase is optional until google-services.json is added.
    }
  }
}
