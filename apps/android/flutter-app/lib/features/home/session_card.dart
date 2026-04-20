import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/widgets/metric_chip.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/live'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                child: Icon(summary.agent == AgentKind.claude
                    ? Icons.auto_awesome_rounded
                    : Icons.terminal_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.agent.label, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Last activity ${DateFormat.Hm().format(summary.lastActivity)}'),
                  ],
                ),
              ),
              MetricChip(
                icon: summary.mode == 'cloud' ? Icons.cloud_done_rounded : Icons.laptop_rounded,
                label: summary.mode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
