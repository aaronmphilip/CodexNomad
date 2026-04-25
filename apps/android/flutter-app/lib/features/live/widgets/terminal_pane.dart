import 'dart:async';

import 'package:codex_nomad/features/live/widgets/diff_card.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.state,
    required this.controller,
  });

  final LiveSessionState state;
  final SessionController controller;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final TextEditingController _input = TextEditingController();
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _appendNewline = true;

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.terminal.length != widget.state.terminal.length) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rawTerminalText = widget.state.terminal.map((e) => e.text).join();
    final terminalText = rawTerminalText.isEmpty
        ? _emptyTerminalText(widget.state)
        : rawTerminalText;
    final query = _search.text.trim().toLowerCase();
    final filteredText = query.isEmpty
        ? terminalText
        : terminalText
            .split('\n')
            .where((line) => line.toLowerCase().contains(query))
            .join('\n');
    final visibleText = filteredText.trim().isEmpty && query.isNotEmpty
        ? 'No matching lines.'
        : filteredText;
    final lineCount = rawTerminalText.isEmpty
        ? 0
        : '\n'.allMatches(rawTerminalText).length + 1;
    final canSend = widget.state.status == ConnectionStatus.ready;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => widget.controller.interrupt(),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Interrupt'),
              ),
              OutlinedButton.icon(
                onPressed: widget.controller.clearTerminalBuffer,
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('Clear view'),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyTerminal(terminalText),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickCommandChip(
                label: 'pwd',
                onTap: () => _sendPreset('pwd'),
              ),
              _QuickCommandChip(
                label: 'ls -la',
                onTap: () => _sendPreset('ls -la'),
              ),
              _QuickCommandChip(
                label: 'git status',
                onTap: () => _sendPreset('git status'),
              ),
              _QuickCommandChip(
                label: 'npm test',
                onTap: () => _sendPreset('npm test'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search terminal output',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$lineCount lines',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            children: [
              if (widget.state.diffs.isNotEmpty) ...[
                for (final diff in widget.state.diffs)
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
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    visibleText,
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
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: _appendNewline ? 'Send with newline' : 'Raw send',
                  onPressed: () {
                    setState(() => _appendNewline = !_appendNewline);
                  },
                  icon: Icon(
                    _appendNewline
                        ? Icons.keyboard_return_rounded
                        : Icons.input_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: canSend,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      hintText: 'Run terminal command...',
                    ),
                    onSubmitted: (_) => _sendInput(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Send terminal input',
                  onPressed: canSend ? _sendInput : null,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _sendPreset(String value) {
    _input.text = value;
    _sendInput();
  }

  void _sendInput() {
    final value = _input.text;
    if (value.trim().isEmpty) return;
    unawaited(
      widget.controller.sendTerminalInput(
        value,
        appendNewline: _appendNewline,
      ),
    );
    _input.clear();
  }

  Future<void> _copyTerminal(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Terminal output copied')),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _emptyTerminalText(LiveSessionState state) {
    if (state.status == ConnectionStatus.connecting) {
      return 'Connecting to relay...';
    }
    if (state.status == ConnectionStatus.disconnected) {
      final detail = (state.error ?? '').trim();
      if (detail.isEmpty) {
        return 'Disconnected. Reconnect to continue.';
      }
      return 'Disconnected: $detail';
    }
    if (state.status == ConnectionStatus.error) {
      final detail = (state.error ?? '').trim();
      if (detail.isEmpty) {
        return 'Session error. Restart local session from desktop.';
      }
      return 'Session error: $detail';
    }
    if (state.status == ConnectionStatus.ended) {
      return 'Session ended. Start a new local session to continue.';
    }
    return 'Waiting for terminal output...';
  }
}

class _QuickCommandChip extends StatelessWidget {
  const _QuickCommandChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: onTap,
      avatar: const Icon(Icons.terminal_rounded, size: 16),
      label: Text(label),
    );
  }
}
