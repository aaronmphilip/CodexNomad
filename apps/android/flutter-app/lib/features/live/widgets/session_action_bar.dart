import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';

class SessionActionBar extends StatelessWidget {
  const SessionActionBar({super.key, required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
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
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Interrupt',
            onPressed: () => controller.interrupt(),
            icon: const Icon(Icons.stop_rounded),
          ),
        ],
      ),
    );
  }
}
