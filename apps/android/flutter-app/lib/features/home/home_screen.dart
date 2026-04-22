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
    final scheme = Theme.of(context).colorScheme;

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
            const SizedBox(height: 10),
            const Center(child: CodexNomadMark(size: 112, showFrame: false)),
            const SizedBox(height: 28),
            Text(
              'Start working',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 0.98,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Run Codex or Claude on your computer. Control the session from your phone with chat, terminal, files, and approvals.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: () => context.push('/start'),
              icon: const Text(
                '</',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              label: const Text('Start working'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.lastPairing == null
                  ? null
                  : () async {
                      final ok = await ref
                          .read(sessionControllerProvider)
                          .reconnectLastPairing();
                      if (context.mounted && ok) context.go('/live');
                    },
              icon: const Icon(PhosphorIconsRegular.arrowsClockwise),
              label: const Text('Reconnect last machine'),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _SignalTile(
                    icon: PhosphorIconsRegular.lockKey,
                    label: 'Relay',
                    value: 'E2EE',
                    active: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SignalTile(
                    icon: PhosphorIconsRegular.laptop,
                    label: 'Mode',
                    value: 'Local',
                    active: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SignalTile(
                    icon: PhosphorIconsRegular.bellRinging,
                    label: 'Queue',
                    value: '${state.inbox.length}',
                    active: state.inbox.isNotEmpty,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            _SectionHeader(
              title: 'Recent chats',
              trailing: sessions.isEmpty ? 'None' : '${sessions.length}',
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const _EmptyRecent()
            else
              for (final session in sessions.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecentChatTile(summary: session),
                ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Needs attention',
              trailing: state.inbox.isEmpty ? 'Clear' : '${state.inbox.length}',
            ),
            const SizedBox(height: 12),
            if (state.inbox.isEmpty)
              const _EmptyAttention()
            else
              for (final item in state.inbox.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AttentionTile(item: item),
                ),
          ],
        ),
      ),
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
      height: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          Text(
            label,
            maxLines: 1,
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
  const _RecentChatTile({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go('/live'),
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
                      summary.agent.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      summary.machineName,
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
}

class _AttentionTile extends StatelessWidget {
  const _AttentionTile({required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        onTap: () => context.go('/live'),
        leading:
            Icon(PhosphorIconsRegular.warningCircle, color: scheme.primary),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          item.detail,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(PhosphorIconsRegular.arrowRight),
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
