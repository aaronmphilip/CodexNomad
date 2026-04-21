import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';

class DiffCard extends StatelessWidget {
  const DiffCard({
    super.key,
    required this.model,
    required this.controller,
  });

  final DiffCardModel model;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: Icon(Icons.difference_rounded, color: scheme.primary),
        title:
            Text(model.filePath, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(model.summary),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              model.patch,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              maxLines: 14,
              overflow: TextOverflow.fade,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => controller.approve(),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => controller.reject(),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
