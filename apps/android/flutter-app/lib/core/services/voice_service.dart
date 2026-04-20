import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText _speech = SpeechToText();

  Future<String?> listenOnce() async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) return null;
    final available = await _speech.initialize();
    if (!available) return null;

    String result = '';
    await _speech.listen(onResult: (value) => result = value.recognizedWords);
    await Future<void>.delayed(const Duration(seconds: 4));
    await _speech.stop();
    return result.trim().isEmpty ? null : result.trim();
  }
}
