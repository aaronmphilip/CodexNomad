import 'package:codex_nomad/features/live/widgets/diff_card.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';

class TerminalPane extends StatelessWidget {
  const TerminalPane({
    super.key,
    required this.state,
    required this.controller,
  });

  final LiveSessionState state;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        if (state.diffs.isNotEmpty) ...[
          for (final diff in state.diffs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DiffCard(model: diff),
            ),
        ],
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.brightness == Brightness.dark
                ? const Color(0xFF070A0A)
                : const Color(0xFF101414),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              state.terminal.isEmpty
                  ? 'Waiting for terminal output...'
                  : state.terminal.map((e) => e.text).join(),
              style: const TextStyle(
                color: Color(0xFFE6FFFA),
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.32,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
