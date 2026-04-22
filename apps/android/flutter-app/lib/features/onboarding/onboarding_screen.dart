import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _installCommand = 'sh scripts/dev/install-local-unix.sh';
  static const _windowsInstallCommand =
      r'powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\install-local-windows.ps1';

  final _pageController = PageController();
  int _page = 0;
  AgentKind _agent = AgentKind.codex;

  String get _pairCommand {
    return _agent == AgentKind.claude
        ? 'codexnomad pair claude'
        : 'codexnomad pair';
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = _steps(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              page: _page,
              count: steps.length,
              onSkip: _finishToHome,
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: steps.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) => steps[index],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.96),
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: _BottomControls(
                page: _page,
                count: steps.length,
                onBack: _page == 0 ? null : _previous,
                onNext: _page == steps.length - 1 ? _finishToScanner : _next,
                onSecondary: _finishToHome,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _steps(BuildContext context) {
    return [
      _OnboardingPage(
        icon: PhosphorIconsRegular.shieldCheck,
        eyebrow: 'Local Free',
        title: 'Your phone becomes the control room.',
        body:
            'Codex Nomad lets the phone control Codex or Claude Code running on your own computer. The laptop stays in charge of the agent; the phone handles pairing, approvals, terminal output, files, and blocked-work alerts.',
        why:
            'This keeps API keys and local dev tools on the machine where they already live.',
        children: const [
          _TrustRow(
            icon: PhosphorIconsRegular.lockKey,
            title: 'Encrypted session',
            detail: 'The relay routes ciphertext, not terminal text.',
          ),
          _TrustRow(
            icon: PhosphorIconsRegular.laptop,
            title: 'PC stays on',
            detail: 'Local mode stops when the computer sleeps or shuts down.',
          ),
          _TrustRow(
            icon: PhosphorIconsRegular.bellRinging,
            title: 'Blocked-agent alerts',
            detail: 'Approvals and errors come to the phone first.',
          ),
        ],
      ),
      _OnboardingPage(
        icon: PhosphorIconsRegular.downloadSimple,
        eyebrow: 'Step 1',
        title: 'Set up the desktop daemon once.',
        body:
            'Install Codex Nomad from this repo on the computer where Codex or Claude Code is already signed in. The public installer URL is not live yet, so this test build uses local install commands.',
        why:
            'The phone should never need your OpenAI, Anthropic, GitHub, or shell credentials.',
        children: [
          _CommandBlock(
            title: 'macOS or Linux repo root',
            command: _installCommand,
            onCopy: () => _copy(_installCommand),
          ),
          _CommandBlock(
            title: 'Windows PowerShell repo root',
            command: _windowsInstallCommand,
            onCopy: () => _copy(_windowsInstallCommand),
          ),
          _CommandBlock(
            title: 'Check readiness',
            command: 'codexnomad doctor',
            onCopy: () => _copy('codexnomad doctor'),
          ),
        ],
      ),
      _OnboardingPage(
        icon: PhosphorIconsRegular.terminalWindow,
        eyebrow: 'Step 2',
        title: 'Start the agent you want to control.',
        body:
            'Pick Codex or Claude, then run the command on your computer. It creates a short-lived QR code for this phone and this session.',
        why:
            'Short-lived pairing reduces risk if somebody screenshots or reuses an old code.',
        children: [
          SegmentedButton<AgentKind>(
            segments: const [
              ButtonSegment(
                value: AgentKind.codex,
                icon: Icon(PhosphorIconsRegular.terminal),
                label: Text('Codex'),
              ),
              ButtonSegment(
                value: AgentKind.claude,
                icon: Icon(PhosphorIconsRegular.sparkle),
                label: Text('Claude'),
              ),
            ],
            selected: {_agent},
            onSelectionChanged: (value) => setState(() => _agent = value.first),
          ),
          const SizedBox(height: 12),
          _CommandBlock(
            title: 'Run on your computer',
            command: _pairCommand,
            onCopy: () => _copy(_pairCommand),
          ),
          const _TrustRow(
            icon: PhosphorIconsRegular.warningCircle,
            title: 'Keep the terminal open',
            detail: 'Closing it ends the local agent session.',
          ),
        ],
      ),
      _OnboardingPage(
        icon: PhosphorIconsRegular.qrCode,
        eyebrow: 'Step 3',
        title: 'Scan the QR and run from the phone.',
        body:
            'After scanning, the live session opens. You can send input, review diffs, approve or reject requests, browse files, and reconnect to the last trusted machine.',
        why:
            'You stay mobile, but every risky action still waits for your explicit approval.',
        children: const [
          _TrustRow(
            icon: PhosphorIconsRegular.camera,
            title: 'Camera scan',
            detail: 'Aim at the QR printed by the desktop daemon.',
          ),
          _TrustRow(
            icon: PhosphorIconsRegular.arrowsClockwise,
            title: 'Reconnect later',
            detail: 'Trusted machine details are saved locally on this phone.',
          ),
          _TrustRow(
            icon: PhosphorIconsRegular.cloudWarning,
            title: 'Cloud is different',
            detail:
                'Cloud runners can work while the laptop is off, but local mode cannot.',
          ),
        ],
      ),
    ];
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $value')),
    );
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _previous() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finishToHome() async {
    await ref.read(onboardingControllerProvider).complete();
    if (mounted) context.go('/');
  }

  Future<void> _finishToScanner() async {
    await ref.read(onboardingControllerProvider).complete();
    if (mounted) context.go('/scan');
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.page,
    required this.count,
    required this.onSkip,
  });

  final int page;
  final int count;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
      child: Row(
        children: [
          const CodexNomadMark(size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Codex Nomad',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          _PageDots(page: page, count: count),
          const SizedBox(width: 6),
          TextButton(
            onPressed: onSkip,
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.page, required this.count});

  final int page;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: i == page ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: i == page
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.22),
            ),
          ),
      ],
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.why,
    required this.children,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  final String why;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: scheme.primary.withValues(alpha: 0.14),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.38)),
          ),
          child: Icon(icon, color: scheme.primary, size: 34),
        ),
        const SizedBox(height: 24),
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.secondary,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1.02,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.86),
                height: 1.38,
              ),
        ),
        const SizedBox(height: 18),
        _WhyPanel(text: why),
        const SizedBox(height: 20),
        ...children.expand((child) => [child, const SizedBox(height: 12)]),
      ],
    );
  }
}

class _WhyPanel extends StatelessWidget {
  const _WhyPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.info, color: scheme.secondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.86),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({
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
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.82)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: scheme.primary.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: scheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
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

class _CommandBlock extends StatelessWidget {
  const _CommandBlock({
    required this.title,
    required this.command,
    required this.onCopy,
  });

  final String title;
  final String command;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF08050D),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(PhosphorIconsRegular.terminal, color: scheme.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  command,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Copy command',
                onPressed: onCopy,
                icon: const Icon(PhosphorIconsRegular.copy),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.page,
    required this.count,
    required this.onBack,
    required this.onNext,
    required this.onSecondary,
  });

  final int page;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSecondary;

  bool get _last => page == count - 1;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(PhosphorIconsRegular.arrowLeft),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: onSecondary,
            child: const Text('Inbox'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: onNext,
            icon: Icon(
              _last
                  ? PhosphorIconsRegular.qrCode
                  : PhosphorIconsRegular.arrowRight,
            ),
            label: Text(_last ? 'Pair now' : 'Continue'),
          ),
        ),
      ],
    );
  }
}
