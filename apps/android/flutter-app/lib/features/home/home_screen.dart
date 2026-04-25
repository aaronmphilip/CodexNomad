import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(sessionControllerProvider);
    final state = controller.state;
    final sessions = controller.recentSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex Nomad'),
        actions: [
          IconButton(
            tooltip: 'Machines',
            onPressed: () => context.push('/machines'),
            icon: const Icon(PhosphorIconsRegular.laptop),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(PhosphorIconsRegular.slidersHorizontal),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          children: [
            _InboxHeader(
              blockedCount: state.inbox.length,
              liveCount: sessions
                  .where((session) =>
                      session.status == ConnectionStatus.ready ||
                      session.status == ConnectionStatus.connecting)
                  .length,
              lastMachine: controller.lastPairing?.machineName,
            ),
            const SizedBox(height: 18),
            _PrimaryActions(
              canReconnect: controller.lastPairing != null,
              onStart: () => context.push('/start'),
              onCloud: () => context.push('/cloud'),
              onReconnect: () async {
                final ok = await ref
                    .read(sessionControllerProvider)
                    .reconnectLastPairing();
                if (context.mounted && ok) context.go('/live');
              },
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = (constraints.maxWidth - 20) / 3;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: _SignalTile(
                        icon: PhosphorIconsRegular.lockKey,
                        label: 'Relay',
                        value: 'E2EE',
                        active: true,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _SignalTile(
                        icon: PhosphorIconsRegular.laptop,
                        label: 'Mode',
                        value: 'Local',
                        active: true,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _SignalTile(
                        icon: PhosphorIconsRegular.bellRinging,
                        label: 'Queue',
                        value: '${state.inbox.length}',
                        active: state.inbox.isNotEmpty,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            _SectionHeader(
              title: 'Needs attention',
              trailing: state.inbox.isEmpty ? 'Clear' : '${state.inbox.length}',
            ),
            const SizedBox(height: 12),
            if (state.inbox.isEmpty)
              const _EmptyAttention()
            else
              for (final item in state.inbox.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AttentionTile(
                    item: item,
                    controller: controller,
                  ),
                ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Recent projects',
              trailing: sessions.isEmpty ? 'None' : '${sessions.length}',
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const _EmptyRecent()
            else
              for (final session in sessions.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentChatTile(
                    summary: session,
                    onTap: () {
                      ref
                          .read(sessionControllerProvider)
                          .openHistory(session.id)
                          .then((_) {
                        if (context.mounted) context.go('/live');
                      });
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _InboxHeader extends StatelessWidget {
  const _InboxHeader({
    required this.blockedCount,
    required this.liveCount,
    required this.lastMachine,
  });

  final int blockedCount;
  final int liveCount;
  final String? lastMachine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasBlocked = blockedCount > 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: hasBlocked
            ? scheme.error.withValues(alpha: 0.12)
            : scheme.primary.withValues(alpha: 0.10),
        border: Border.all(
          color: hasBlocked
              ? scheme.error.withValues(alpha: 0.28)
              : scheme.primary.withValues(alpha: 0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CodexNomadMark(size: 44, showFrame: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBlocked ? '$blockedCount blocked' : 'Agent inbox clear',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.04,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  liveCount > 0
                      ? '$liveCount live session${liveCount == 1 ? '' : 's'} running.'
                      : lastMachine == null
                          ? 'Start a local Codex or Claude run from this phone.'
                          : 'Last machine: $lastMachine',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.25,
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

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({
    required this.canReconnect,
    required this.onStart,
    required this.onCloud,
    required this.onReconnect,
  });

  final bool canReconnect;
  final VoidCallback onStart;
  final VoidCallback onCloud;
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onStart,
          icon: const Text(
            '</',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          label: const Text('New one-shot local run'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canReconnect ? onReconnect : null,
                icon: const Icon(PhosphorIconsRegular.arrowsClockwise),
                label: const Text('Reconnect'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCloud,
                icon: const Icon(Icons.cloud_queue_rounded),
                label: const Text('Cloud preview'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _RecentChatTile extends StatelessWidget {
  const _RecentChatTile({required this.summary, required this.onTap});

  final SessionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.command, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.workspaceRoot.isEmpty
                          ? summary.title.isEmpty
                              ? summary.agent.label
                              : summary.title
                          : summary.title.isEmpty
                              ? _workspaceName(summary.workspaceRoot)
                              : summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      summary.workspaceRoot.isEmpty
                          ? summary.machineName
                          : summary.workspaceRoot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(PhosphorIconsRegular.arrowRight),
            ],
          ),
        ),
      ),
    );
  }

  String _workspaceName(String root) {
    final value = root.trim().replaceAll('\\', '/');
    if (value.isEmpty) return summary.agent.label;
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? value : parts.last;
  }
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({
    required this.item,
    required this.controller,
  });

  final AttentionItem item;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPermission = item.kind == AttentionKind.permission;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () => context.go('/live'),
              leading: Icon(PhosphorIconsRegular.warningCircle,
                  color: scheme.primary),
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                item.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(PhosphorIconsRegular.arrowRight),
            ),
            if (isPermission) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => controller.approve(item.id),
                      child: const Text('Approve'),
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    return const _EmptyPanel(
      icon: PhosphorIconsRegular.terminalWindow,
      text: 'No chats yet. Start working to connect your first local agent.',
    );
  }
}

class _EmptyAttention extends StatelessWidget {
  const _EmptyAttention();

  @override
  Widget build(BuildContext context) {
    return const _EmptyPanel(
      icon: PhosphorIconsRegular.checkCircle,
      text: 'No blocked agents. Approval requests appear here.',
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: scheme.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
