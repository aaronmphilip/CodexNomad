import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class StartWorkScreen extends ConsumerStatefulWidget {
  const StartWorkScreen({super.key});

  @override
  ConsumerState<StartWorkScreen> createState() => _StartWorkScreenState();
}

class _StartWorkScreenState extends ConsumerState<StartWorkScreen> {
  static const _windowsCodexInstallCommand = 'npm.cmd install -g @openai/codex';
  static const _windowsCodexLoginCommand = 'codex.cmd login';

  AgentKind _agent = AgentKind.codex;
  final _workspace = TextEditingController(text: '.');
  final _prompt = TextEditingController();
  bool _reliableMode = true;

  String get _command {
    final agent = _agent == AgentKind.claude ? 'claude' : 'codex';
    final workspace =
        _workspace.text.trim().isEmpty ? '.' : _workspace.text.trim();
    final allowAppsMcp =
        _agent == AgentKind.codex && !_reliableMode ? ' -AllowAppsMcp' : '';
    return 'powershell -NoProfile -ExecutionPolicy Bypass -File .\\scripts\\dev\\start-local-test-windows.ps1 -Agent $agent -Workspace ${_psQuote(workspace)}$allowAppsMcp';
  }

  @override
  void initState() {
    super.initState();
    _workspace.addListener(_refreshCommand);
    _prompt.addListener(_refreshCommand);
  }

  @override
  void dispose() {
    _workspace.removeListener(_refreshCommand);
    _prompt.removeListener(_refreshCommand);
    _workspace.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _refreshCommand() {
    if (mounted) setState(() {});
  }

  String _psQuote(String value) {
    return "'${value.replaceAll("'", "''")}'";
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
              'One prompt, then leave the desk',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1.02,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Write the task here, start the local agent on your computer, scan the QR, and the phone sends the first prompt automatically.',
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
            TextField(
              controller: _workspace,
              decoration: const InputDecoration(
                prefixIcon: Icon(PhosphorIconsRegular.folderOpen),
                labelText: 'Project folder',
                hintText: 'C:\\Users\\you\\Desktop\\your-app',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prompt,
              minLines: 5,
              maxLines: 9,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                prefixIcon: Icon(PhosphorIconsRegular.command),
                labelText: 'One-shot task',
                hintText:
                    'Build the feature end to end, run tests, fix failures, and summarize what changed.',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _agent == AgentKind.codex ? _reliableMode : false,
              onChanged: _agent == AgentKind.codex
                  ? (value) => setState(() => _reliableMode = value)
                  : null,
              secondary: const Icon(Icons.verified_user_rounded),
              title: const Text('Reliable mode'),
              subtitle: Text(
                _agent == AgentKind.codex
                    ? 'Disables Apps MCP for Codex to avoid startup timeout and no-reply sessions.'
                    : 'Only applies to Codex sessions.',
              ),
            ),
            if (_agent == AgentKind.codex) ...[
              const SizedBox(height: 8),
              _PrerequisiteCard(
                installCommand: _windowsCodexInstallCommand,
                loginCommand: _windowsCodexLoginCommand,
                onCopyInstall: () => _copyValue(_windowsCodexInstallCommand),
                onCopyLogin: () => _copyValue(_windowsCodexLoginCommand),
              ),
            ],
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
              title: 'Scan and send',
              detail: _prompt.text.trim().isEmpty
                  ? 'The phone opens the scanner, then you can send the first task in Chat.'
                  : 'After pairing, this task is sent to the agent automatically.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _scanAndQueuePrompt,
              icon: const Icon(PhosphorIconsRegular.checkCircle),
              label: Text(
                _prompt.text.trim().isEmpty
                    ? 'Scan pairing QR'
                    : 'Scan and send prompt',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push('/cloud'),
              icon: const Icon(Icons.cloud_rounded),
              label: const Text('Use cloud mode'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy() async {
    await _copyValue(_command);
  }

  void _scanAndQueuePrompt() {
    ref.read(sessionControllerProvider).queueLaunchPrompt(_prompt.text);
    context.push('/scan');
  }

  Future<void> _copyValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $value')),
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

class _PrerequisiteCard extends StatelessWidget {
  const _PrerequisiteCard({
    required this.installCommand,
    required this.loginCommand,
    required this.onCopyInstall,
    required this.onCopyLogin,
  });

  final String installCommand;
  final String loginCommand;
  final VoidCallback onCopyInstall;
  final VoidCallback onCopyLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.34),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'First-time Codex setup (one time per machine)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Run these once before Local mode. Skip if Codex CLI is already installed and logged in.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          _PrerequisiteCommandRow(
            label: 'Install Codex CLI',
            command: installCommand,
            onCopy: onCopyInstall,
          ),
          const SizedBox(height: 8),
          _PrerequisiteCommandRow(
            label: 'Login Codex CLI',
            command: loginCommand,
            onCopy: onCopyLogin,
          ),
        ],
      ),
    );
  }
}

class _PrerequisiteCommandRow extends StatelessWidget {
  const _PrerequisiteCommandRow({
    required this.label,
    required this.command,
    required this.onCopy,
  });

  final String label;
  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF090511),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  command,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Copy command',
            onPressed: onCopy,
            icon: const Icon(PhosphorIconsRegular.copy),
          ),
        ],
      ),
    );
  }
}
