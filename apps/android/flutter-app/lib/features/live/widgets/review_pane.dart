import 'package:codex_nomad/features/live/widgets/diff_card.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ReviewPane extends StatelessWidget {
  const ReviewPane({
    super.key,
    required this.state,
    required this.controller,
  });

  final LiveSessionState state;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final attention = state.inbox
        .where((item) =>
            item.kind == AttentionKind.permission ||
            item.kind == AttentionKind.diff ||
            item.kind == AttentionKind.error ||
            item.kind == AttentionKind.connection)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: [
        Text(
          'Review Queue',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        if (attention.isEmpty)
          const _EmptyReview()
        else
          for (final item in attention)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttentionReviewCard(
                item: item,
                controller: controller,
              ),
            ),
        if (state.diffs.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Diffs',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          for (final diff in state.diffs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DiffCard(model: diff, controller: controller),
            ),
        ],
      ],
    );
  }
}

class _AttentionReviewCard extends StatelessWidget {
  const _AttentionReviewCard({
    required this.item,
    required this.controller,
  });

  final AttentionItem item;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (item.tone) {
      AttentionTone.success => Colors.green,
      AttentionTone.warning => Colors.amber.shade700,
      AttentionTone.danger => scheme.error,
      AttentionTone.info => scheme.primary,
    };
    final needsDecision = item.kind == AttentionKind.permission;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.detail,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (needsDecision) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => controller.approve(),
                      icon: const Icon(PhosphorIconsRegular.checkCircle),
                      label: const Text('Approve once'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => controller.reject(),
                      icon: const Icon(PhosphorIconsRegular.xCircle),
                      label: const Text('Deny'),
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

class _EmptyReview extends StatelessWidget {
  const _EmptyReview();

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
                'No approval or diff is waiting. The terminal stays available when you need raw detail.',
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
