import 'package:codex_nomad/core/services/voice_service.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';

class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.controller,
    required this.state,
  });

  final SessionController controller;
  final LiveSessionState state;

  @override
  State<ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<ChatPane> {
  final _text = TextEditingController();
  final _voice = VoiceService();
  bool _listening = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final chunk in widget.state.terminal.take(80))
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Text(
                      chunk.text.trim().isEmpty ? '...' : chunk.text.trim(),
                      maxLines: 8,
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Voice input',
                onPressed: _listening
                    ? null
                    : () async {
                        setState(() => _listening = true);
                        final words = await _voice.listenOnce();
                        setState(() => _listening = false);
                        if (words != null) _text.text = words;
                      },
                icon: Icon(_listening ? Icons.hearing_rounded : Icons.mic_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  decoration: const InputDecoration(
                    hintText: 'Tell the agent what to do...',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: _send,
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    widget.controller.sendText(value);
    _text.clear();
  }
}
