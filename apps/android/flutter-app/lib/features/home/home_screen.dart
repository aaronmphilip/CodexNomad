import 'package:codex_nomad/features/home/session_card.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(sessionControllerProvider);
    final sessions = controller.recentSessions;
    final state = controller.state;
    final auth = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    final inboxItems = state.inbox;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agent Inbox'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan'),
        icon: const Icon(PhosphorIconsRegular.qrCode),
        label: const Text('Pair local'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            _LocalStatusPanel(
              lastPairing: controller.lastPairing,
              onScan: () => context.push('/scan'),
              onReconnect: controller.lastPairing == null
                  ? null
                  : () async {
                      final connected = await ref
                          .read(sessionControllerProvider)
                          .reconnectLastPairing();
                      if (context.mounted && connected) context.push('/live');
                    },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    icon: PhosphorIconsRegular.robot,
                    label: 'Agents',
                    value: '${sessions.length}',
                    active: sessions.isNotEmpty,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: _MetricTile(
                    icon: PhosphorIconsRegular.laptop,
                    label: 'Mode',
                    value: 'Local',
                    active: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricTile(
                    icon: PhosphorIconsRegular.bellRinging,
                    label: 'Actions',
                    value: '${inboxItems.length}',
                    active: inboxItems.isNotEmpty,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Needs Attention',
              trailing: inboxItems.isEmpty ? 'Clear' : '${inboxItems.length}',
            ),
            const SizedBox(height: 12),
            if (inboxItems.isEmpty)
              const _EmptyInbox()
            else
              for (final item in inboxItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _InboxCard(item: item),
                ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: 'Local Sessions',
              trailing: sessions.isEmpty ? 'None' : '${sessions.length}',
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(PhosphorIconsRegular.terminalWindow,
                          color: scheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'No live local agent',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Run codexnomad pair on your computer, then scan the QR.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...sessions.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SessionCard(summary: s),
                  )),
            const SizedBox(height: 22),
            if (!auth.configured)
              _AuthNudge(
                text:
                    'Supabase auth is not configured. Local sessions still work.',
                icon: Icons.info_outline_rounded,
              )
            else if (!auth.signedIn)
              _AuthNudge(
                text: 'Sign in from Settings to sync session history.',
                icon: Icons.lock_open_rounded,
              ),
          ],
        ),
      ),
    );
  }
}

class _LocalStatusPanel extends StatelessWidget {
  const _LocalStatusPanel({
    required this.onScan,
    required this.lastPairing,
    required this.onReconnect,
  });

  final VoidCallback onScan;
  final PairingPayload? lastPairing;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.72)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsRegular.shieldCheck, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Free Local Mode',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'One command on your machine. Full control from your phone.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.08,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Pair once, then handle prompts, diffs, and blocked sessions from the inbox.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(PhosphorIconsRegular.qrCode),
            label: const Text('Scan local QR'),
          ),
          if (lastPairing != null) ...[
            const SizedBox(height: 12),
            _LastMachineRow(
              pairing: lastPairing!,
              onReconnect: onReconnect,
            ),
          ],
        ],
      ),
    );
  }
}

class _LastMachineRow extends StatelessWidget {
  const _LastMachineRow({
    required this.pairing,
    required this.onReconnect,
  });

  final PairingPayload pairing;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surface.withValues(alpha: 0.5),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.laptop, color: scheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pairing.machineName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  pairing.isExpired
                      ? 'Pairing expired'
                      : '${pairing.agent.label} - ${pairing.machineOs.isEmpty ? 'local' : pairing.machineOs}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: onReconnect,
            child: Text(pairing.isExpired ? 'Resume' : 'Reconnect'),
          ),
        ],
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
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
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
      height: 86,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.54),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
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
                  fontWeight: FontWeight.w800,
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

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.checkCircle, color: Colors.green),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No blocked agents. When Codex or Claude needs you, it appears here first.',
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

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.item});

  final AttentionItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (item.tone) {
      AttentionTone.success => Colors.green,
      AttentionTone.warning => Colors.amber.shade700,
      AttentionTone.danger => scheme.error,
      AttentionTone.info => scheme.primary,
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/live'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_iconFor(item.kind), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.actionLabel ?? '',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(width: 6),
              Icon(
                PhosphorIconsRegular.arrowRight,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(AttentionKind kind) {
    return switch (kind) {
      AttentionKind.permission => PhosphorIconsRegular.shieldWarning,
      AttentionKind.diff => PhosphorIconsRegular.gitDiff,
      AttentionKind.blocked => PhosphorIconsRegular.warning,
      AttentionKind.complete => PhosphorIconsRegular.checkCircle,
      AttentionKind.connection => PhosphorIconsRegular.cloudWarning,
      AttentionKind.error => PhosphorIconsRegular.warningCircle,
    };
  }
}

class _AuthNudge extends StatelessWidget {
  const _AuthNudge({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
