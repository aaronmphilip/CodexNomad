import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class MachinesScreen extends ConsumerWidget {
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(sessionControllerProvider);
    final pairing = controller.lastPairing;
    final sessions = controller.recentSessions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Machines'),
        actions: [
          IconButton(
            tooltip: 'Pair local',
            onPressed: () => context.push('/scan'),
            icon: const Icon(PhosphorIconsRegular.qrCode),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (pairing == null)
              _EmptyMachines(onPair: () => context.push('/scan'))
            else
              _MachineCard(
                pairing: pairing,
                status: controller.state.status,
                onReconnect: () async {
                  final connected = await ref
                      .read(sessionControllerProvider)
                      .reconnectLastPairing();
                  if (context.mounted && connected) context.push('/live');
                },
              ),
            const SizedBox(height: 22),
            Text(
              'Session History',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const _EmptyHistory()
            else
              for (final session in sessions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SessionRow(summary: session),
                ),
          ],
        ),
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({
    required this.pairing,
    required this.status,
    required this.onReconnect,
  });

  final PairingPayload pairing;
  final ConnectionStatus status;
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: scheme.primary.withValues(alpha: 0.12),
                  ),
                  child:
                      Icon(PhosphorIconsRegular.laptop, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pairing.machineName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      Text(
                        _machineSubtitle(pairing),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(status: status),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MachineMetric(
                    label: 'Agent',
                    value: pairing.agent.label,
                    icon: PhosphorIconsRegular.robot,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MachineMetric(
                    label: 'Mode',
                    value: pairing.mode,
                    icon: PhosphorIconsRegular.broadcast,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onReconnect,
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              label: Text(pairing.isExpired ? 'Resume trusted' : 'Reconnect'),
            ),
          ],
        ),
      ),
    );
  }

  String _machineSubtitle(PairingPayload pairing) {
    final os = pairing.machineOs.isEmpty ? 'local' : pairing.machineOs;
    final id =
        pairing.machineId.isEmpty ? pairing.sessionId : pairing.machineId;
    final shortId = id.length <= 10 ? id : id.substring(0, 10);
    return '$os - $shortId';
  }
}

class _MachineMetric extends StatelessWidget {
  const _MachineMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = status == ConnectionStatus.ready ||
        status == ConnectionStatus.connecting;
    final color = active ? Colors.green : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        _label(status),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  String _label(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connecting => 'Connecting',
      ConnectionStatus.ready => 'Online',
      ConnectionStatus.error => 'Error',
      ConnectionStatus.ended => 'Ended',
      _ => 'Offline',
    };
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          summary.agent == AgentKind.claude
              ? PhosphorIconsRegular.sparkle
              : PhosphorIconsRegular.terminalWindow,
          color: scheme.primary,
        ),
        title: Text(
          summary.machineName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${summary.agent.label} - ${summary.machineOs.isEmpty ? summary.mode : summary.machineOs}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          PhosphorIconsRegular.arrowRight,
          color: scheme.onSurfaceVariant,
          size: 18,
        ),
        onTap: () => context.push('/live'),
      ),
    );
  }
}

class _EmptyMachines extends StatelessWidget {
  const _EmptyMachines({required this.onPair});

  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(PhosphorIconsRegular.laptop, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'No paired machine',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onPair,
              icon: const Icon(PhosphorIconsRegular.qrCode),
              label: const Text('Pair local'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.clockCounterClockwise,
                color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No sessions yet',
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
