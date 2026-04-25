import 'dart:async';

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
  final _scroll = ScrollController();
  final _voice = VoiceService();
  bool _listening = false;

  @override
  void didUpdateWidget(covariant ChatPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.chat.length != widget.state.chat.length ||
        oldWidget.state.activity.length != widget.state.activity.length ||
        oldWidget.state.agentActivity != widget.state.agentActivity) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.state.pairing?.agent.label ?? 'Agent';
    final mcpStartupFailed = widget.state.mcpStartupFailed;
    final canSend = widget.state.status == ConnectionStatus.ready;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            children: [
              if ((widget.state.agentActivity ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _LiveThinkingBanner(
                    text: widget.state.agentActivity!.trim(),
                  ),
                ),
              if (mcpStartupFailed)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: _AgentBubble(
                    icon: PhosphorIconsRegular.warningCircle,
                    title: 'MCP warning',
                    body:
                        'Codex reported an MCP startup warning. Chat and terminal still run; keep Reliable mode on for local sessions.',
                  ),
                ),
              if (widget.state.inbox.isNotEmpty)
                for (final item in widget.state.inbox.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AttentionBubble(
                      item: item,
                      controller: widget.controller,
                    ),
                  ),
              if (widget.state.chat.isEmpty)
                _AgentBubble(
                  icon: PhosphorIconsRegular.command,
                  title: '$agent is ready',
                  body: 'Send a task. Replies and progress appear here.',
                )
              else
                for (final message in widget.state.chat)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _ChatMessageBubble(message: message),
                  ),
            ],
          ),
        ),
        _Composer(
          text: _text,
          listening: _listening,
          enabled: canSend,
          status: widget.state.status,
          onVoice: _listen,
          onSend: _send,
        ),
      ],
    );
  }

  Future<void> _listen() async {
    if (_listening) return;
    final prefix = _text.text.trim();
    setState(() => _listening = true);
    final words = await _voice.listenOnce(
      onPartial: (partial) {
        if (!mounted) return;
        final combined = prefix.isEmpty ? partial : '$prefix $partial';
        _text.value = TextEditingValue(
          text: combined,
          selection: TextSelection.collapsed(offset: combined.length),
        );
      },
    );
    if (!mounted) return;
    setState(() => _listening = false);
    if (words != null) {
      final combined = prefix.isEmpty ? words : '$prefix $words';
      _text.value = TextEditingValue(
        text: combined,
        selection: TextSelection.collapsed(offset: combined.length),
      );
    }
  }

  void _send() {
    final value = _text.text.trim();
    if (value.isEmpty) return;
    unawaited(widget.controller.sendText(value));
    _text.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }
}

class _LiveThinkingBanner extends StatefulWidget {
  const _LiveThinkingBanner({required this.text});

  final String text;

  @override
  State<_LiveThinkingBanner> createState() => _LiveThinkingBannerState();
}

class _LiveThinkingBannerState extends State<_LiveThinkingBanner> {
  int _frame = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (!mounted) return;
      setState(() => _frame = (_frame + 1) % 4);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dots = '.' * _frame;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.text}$dots',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return switch (message.role) {
      ChatRole.user => _UserBubble(message: message),
      ChatRole.agent => _AssistantBubble(message: message),
      ChatRole.system => _SystemBubble(text: message.text),
    };
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.92,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SelectableText(
            message.text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.94),
                  height: 1.34,
                ),
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = switch (message.delivery) {
      ChatDeliveryStatus.sending => 'Sending',
      ChatDeliveryStatus.sent => '',
      ChatDeliveryStatus.failed => 'Failed',
    };
    final color = message.delivery == ChatDeliveryStatus.failed
        ? scheme.error
        : scheme.primary;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: scheme.primary.withValues(alpha: 0.28),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.38)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SelectableText(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.32,
                    ),
              ),
              if (status.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.64),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _AgentBubble extends StatelessWidget {
  const _AgentBubble({
    required this.icon,
    required this.title,
    required this.body,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String body;
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
          SelectableText(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.88),
                  height: 1.32,
                ),
          ),
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
    required this.enabled,
    required this.status,
    required this.onVoice,
    required this.onSend,
  });

  final TextEditingController text;
  final bool listening;
  final bool enabled;
  final ConnectionStatus status;
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
              onPressed: !enabled || listening ? null : onVoice,
              icon: Icon(listening ? Icons.hearing_rounded : Icons.mic_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: text,
                enabled: enabled,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: listening
                      ? 'Listening...'
                      : enabled
                          ? 'Message Codex or Claude...'
                          : _disabledHint(status),
                ),
                onSubmitted: (_) {
                  if (enabled && !listening) onSend();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: enabled && !listening ? onSend : null,
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }

  String _disabledHint(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connecting => 'Connecting session...',
      ConnectionStatus.disconnected => 'Disconnected. Reconnect first.',
      ConnectionStatus.error => 'Session error. Reconnect first.',
      ConnectionStatus.ended => 'Session ended.',
      _ => 'Waiting for live session...',
    };
  }
}
