import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  final SpeechToText _speech = SpeechToText();

  Future<String?> listenOnce({
    ValueChanged<String>? onPartial,
    Duration listenFor = const Duration(seconds: 9),
    Duration pauseFor = const Duration(seconds: 2),
  }) async {
    final permission = await Permission.microphone.request();
    if (!permission.isGranted) return null;
    final available = await _speech.initialize(
      onStatus: (_) {},
      onError: (_) {},
    );
    if (!available) return null;

    final done = Completer<String?>();
    String result = '';

    Future<void> finish() async {
      if (done.isCompleted) return;
      try {
        await _speech.stop();
      } catch (_) {}
      final trimmed = result.trim();
      done.complete(trimmed.isEmpty ? null : trimmed);
    }

    await _speech.listen(
      listenFor: listenFor,
      pauseFor: pauseFor,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (value) {
        final words = value.recognizedWords.trim();
        if (words.isEmpty) return;
        result = words;
        onPartial?.call(words);
        if (value.finalResult) {
          unawaited(finish());
        }
      },
    );

    unawaited(
      Future<void>.delayed(listenFor + const Duration(milliseconds: 350), () {
        unawaited(finish());
      }),
    );
    return done.future.timeout(
      listenFor + const Duration(seconds: 1),
      onTimeout: () => result.trim().isEmpty ? null : result.trim(),
    );
  }
}
