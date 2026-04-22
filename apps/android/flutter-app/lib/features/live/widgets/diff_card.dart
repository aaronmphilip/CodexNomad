import 'package:codex_nomad/models/session_models.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class DiffCard extends StatelessWidget {
  const DiffCard({
    super.key,
    required this.model,
  });

  final DiffCardModel model;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        leading: Icon(PhosphorIconsRegular.gitDiff, color: scheme.primary),
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
        ],
      ),
    );
  }
}
