import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class StartWorkScreen extends StatefulWidget {
  const StartWorkScreen({super.key});

  @override
  State<StartWorkScreen> createState() => _StartWorkScreenState();
}

class _StartWorkScreenState extends State<StartWorkScreen> {
  AgentKind _agent = AgentKind.codex;

  String get _command {
    final agent = _agent == AgentKind.claude ? 'claude' : 'codex';
    return 'powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\dev\\start-local-test-windows.ps1 -Agent $agent';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start working'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            const Center(child: CodexNomadMark(size: 88, showFrame: false)),
            const SizedBox(height: 24),
            Text(
              'Run this on your computer',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Paste the command in PowerShell from the CodexNomad repo root. It starts the relay and prints the pairing QR.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.34,
                  ),
            ),
            const SizedBox(height: 22),
            SegmentedButton<AgentKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: AgentKind.codex,
                  icon: Icon(PhosphorIconsRegular.terminalWindow),
                  label: Text('Codex'),
                ),
                ButtonSegment(
                  value: AgentKind.claude,
                  icon: Icon(PhosphorIconsRegular.sparkle),
                  label: Text('Claude'),
                ),
              ],
              selected: {_agent},
              onSelectionChanged: (value) =>
                  setState(() => _agent = value.first),
            ),
            const SizedBox(height: 18),
            _CommandPanel(
              command: _command,
              onCopy: _copy,
            ),
            const SizedBox(height: 18),
            _StepCard(
              icon: PhosphorIconsRegular.numberCircleOne,
              title: 'Paste and run',
              detail:
                  'Keep that desktop terminal open. Closing it ends Local mode.',
            ),
            const SizedBox(height: 10),
            _StepCard(
              icon: PhosphorIconsRegular.numberCircleTwo,
              title: 'Wait for the QR',
              detail:
                  'The code is short-lived, so scan the fresh one from this run.',
            ),
            const SizedBox(height: 10),
            _StepCard(
              icon: PhosphorIconsRegular.numberCircleThree,
              title: 'Tap Done',
              detail:
                  'The phone opens the scanner, then shows Connecting and Connected.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/scan'),
              icon: const Icon(PhosphorIconsRegular.checkCircle),
              label: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _command));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Command copied')),
    );
  }
}

class _CommandPanel extends StatelessWidget {
  const _CommandPanel({required this.command, required this.onCopy});

  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF08040F),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '</',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.secondary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Local command',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Copy command',
                onPressed: onCopy,
                icon: const Icon(PhosphorIconsRegular.copy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            command,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.08),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
