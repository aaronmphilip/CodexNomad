import 'package:codex_nomad/core/services/voice_service.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

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
    final recent = widget.state.terminal.length > 60
        ? widget.state.terminal.sublist(widget.state.terminal.length - 60)
        : widget.state.terminal;
    final agent = widget.state.pairing?.agent.label ?? 'Agent';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            children: [
              _SessionHeader(state: widget.state),
              const SizedBox(height: 10),
              if (widget.state.inbox.isNotEmpty)
                for (final item in widget.state.inbox.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AttentionBubble(
                      item: item,
                      controller: widget.controller,
                    ),
                  ),
              if (widget.state.diffs.isNotEmpty)
                for (final diff in widget.state.diffs.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DiffBubble(diff: diff),
                  ),
              if (widget.state.files.any((file) => file.status != 'tracked'))
                _ChangedFilesBubble(files: widget.state.files),
              if (recent.isEmpty)
                _AgentBubble(
                  icon: PhosphorIconsRegular.command,
                  title: '$agent is ready',
                  body:
                      'Send a task below. Raw terminal output stays in the Terminal tab.',
                ),
              for (final chunk in recent)
                if (chunk.text.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _TerminalBubble(text: chunk.text.trim()),
                  ),
            ],
          ),
        ),
        _Composer(
          text: _text,
          listening: _listening,
          onVoice: _listen,
          onSend: _send,
        ),
      ],
    );
  }

  Future<void> _listen() async {
    setState(() => _listening = true);
    final words = await _voice.listenOnce();
    if (!mounted) return;
    setState(() => _listening = false);
    if (words != null) _text.text = words;
  }

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    widget.controller.sendText(value);
    _text.clear();
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.state});

  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pairing = state.pairing;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.lockKey, color: scheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pairing?.agent.label ?? 'Live agent',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  pairing == null
                      ? 'Encrypted local workspace'
                      : '${pairing.machineName} - ${pairing.mode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionBubble extends StatelessWidget {
  const _AttentionBubble({
    required this.item,
    required this.controller,
  });

  final AttentionItem item;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final needsDecision = item.kind == AttentionKind.permission;
    return _AgentBubble(
      icon: PhosphorIconsRegular.shieldWarning,
      title: item.title,
      body: item.detail,
      actions: needsDecision
          ? Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => controller.approve(item.id),
                    child: const Text('Approve once'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => controller.reject(item.id),
                    child: const Text('Deny'),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

class _DiffBubble extends StatelessWidget {
  const _DiffBubble({required this.diff});

  final DiffCardModel diff;

  @override
  Widget build(BuildContext context) {
    return _AgentBubble(
      icon: PhosphorIconsRegular.gitDiff,
      title: diff.summary,
      body: diff.filePath,
      code: diff.patch,
    );
  }
}

class _ChangedFilesBubble extends StatelessWidget {
  const _ChangedFilesBubble({required this.files});

  final List<FileEntry> files;

  @override
  Widget build(BuildContext context) {
    final changed = files.where((file) => file.status != 'tracked').take(5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _AgentBubble(
        icon: PhosphorIconsRegular.files,
        title: 'Files changed',
        body: changed.map((file) => '${file.status}  ${file.path}').join('\n'),
      ),
    );
  }
}

class _TerminalBubble extends StatelessWidget {
  const _TerminalBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final firstLine = text.split('\n').first.trim();
    final title = firstLine.startsWith('>') ? 'Ran command' : 'Terminal';
    return _AgentBubble(
      icon: PhosphorIconsRegular.terminal,
      title: title,
      body: text,
    );
  }
}

class _AgentBubble extends StatelessWidget {
  const _AgentBubble({
    required this.icon,
    required this.title,
    required this.body,
    this.code,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? code;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            maxLines: 8,
            overflow: TextOverflow.fade,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.88),
                  height: 1.32,
                ),
          ),
          if (code != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF07040C),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: 0.20)),
              ),
              child: Text(
                code!,
                maxLines: 12,
                overflow: TextOverflow.fade,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: scheme.onSurface.withValues(alpha: 0.84),
                    ),
              ),
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: 12),
            actions!,
          ],
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.text,
    required this.listening,
    required this.onVoice,
    required this.onSend,
  });

  final TextEditingController text;
  final bool listening;
  final VoidCallback onVoice;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
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
              tooltip: 'Voice input',
              onPressed: listening ? null : onVoice,
              icon: Icon(listening ? Icons.hearing_rounded : Icons.mic_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: text,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'Message Codex...',
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
