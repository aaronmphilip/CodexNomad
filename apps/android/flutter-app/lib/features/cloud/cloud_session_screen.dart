import 'dart:async';

import 'package:codex_nomad/core/config/app_config.dart';
import 'package:codex_nomad/core/services/cloud_session_service.dart';
import 'package:codex_nomad/core/services/supabase_service.dart';
import 'package:codex_nomad/models/pairing_payload.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class CloudSessionScreen extends ConsumerStatefulWidget {
  const CloudSessionScreen({super.key});

  @override
  ConsumerState<CloudSessionScreen> createState() => _CloudSessionScreenState();
}

class _CloudSessionScreenState extends ConsumerState<CloudSessionScreen> {
  final TextEditingController _repo = TextEditingController();
  AgentKind _agent = AgentKind.codex;
  CloudSessionStartResult? _start;
  CloudSessionSnapshot? _snapshot;
  String? _error;
  bool _starting = false;
  bool _polling = false;
  bool _connecting = false;
  DateTime? _startedAt;
  Timer? _ticker;
  late final CloudSessionService _service;

  @override
  void initState() {
    super.initState();
    final config = ref.read(appConfigProvider);
    final supabase = ref.read(supabaseServiceProvider);
    _service = CloudSessionService(config: config, supabase: supabase);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _repo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = ref.watch(appConfigProvider);
    final auth = ref.watch(authControllerProvider);
    final cloudPreviewOnly = !config.enableCloudProvisioning;
    final cloudReady = !cloudPreviewOnly &&
        _hasCloudAuth(config, ref.read(supabaseServiceProvider));
    final busy = _starting || _connecting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Session'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: scheme.primary.withValues(alpha: 0.10),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: 0.24)),
              ),
              child: const Text(
                'Cloud mode is visible in this build so the product path is clear, but provisioning is disabled by default. Local mode is the working v1.',
              ),
            ),
            const SizedBox(height: 14),
            if (cloudPreviewOnly)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview only',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'This build does not start paid cloud runners. Enable CODEXNOMAD_ENABLE_CLOUD only after the backend, billing, DigitalOcean, and Tailscale credentials are production-wired.',
                      ),
                    ],
                  ),
                ),
              )
            else if (!cloudReady)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cloud auth missing',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Set CODEXNOMAD_APP_TOKEN for this app build, or sign in with Supabase in Settings.',
                      ),
                    ],
                  ),
                ),
              ),
            if (!auth.signedIn && auth.configured)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_open_rounded),
                  title: const Text('Signed out'),
                  subtitle: const Text(
                    'Sign in from Settings for user-owned cloud sessions.',
                  ),
                  trailing: TextButton(
                    onPressed: () => context.push('/settings'),
                    child: const Text('Open'),
                  ),
                ),
              ),
            const SizedBox(height: 8),
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
              onSelectionChanged:
                  busy ? null : (value) => setState(() => _agent = value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repo,
              enabled: !busy,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.source_rounded),
                labelText: 'Repo URL (optional)',
                hintText: 'https://github.com/owner/repo.git',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy || !cloudReady ? null : _startCloudSession,
              icon: _starting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(
                cloudPreviewOnly
                    ? 'Cloud provisioning disabled'
                    : _starting
                        ? 'Starting...'
                        : 'Start cloud session',
              ),
            ),
            const SizedBox(height: 12),
            const _CloudFeaturePreview(),
            if ((_error ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Card(
                color: scheme.error.withValues(alpha: 0.14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.error),
                  ),
                ),
              ),
            ],
            if (_start != null) ...[
              const SizedBox(height: 14),
              _CloudProgressCard(
                start: _start!,
                snapshot: _snapshot,
                startedAt: _startedAt,
                connecting: _connecting,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startCloudSession() async {
    if (!ref.read(appConfigProvider).enableCloudProvisioning) {
      setState(() {
        _error = 'Cloud provisioning is disabled in this build.';
      });
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
      _start = null;
      _snapshot = null;
      _connecting = false;
      _startedAt = DateTime.now();
    });
    try {
      final result = await _service.start(
        agent: _agent,
        repoUrl: _repo.text,
      );
      if (!mounted) return;
      setState(() {
        _start = result;
        _starting = false;
      });
      _startPolling(result.serverId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '$error';
      });
    }
  }

  void _startPolling(String serverId) {
    _ticker?.cancel();
    unawaited(_pollOnce(serverId));
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollOnce(serverId));
    });
  }

  Future<void> _pollOnce(String serverId) async {
    if (_polling || !mounted) return;
    _polling = true;
    try {
      final snapshot = await _service.snapshot(serverId);
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      if (snapshot.failed) {
        _ticker?.cancel();
        _ticker = null;
        setState(() {
          _error = 'Cloud runner failed. Start a new cloud session.';
        });
        return;
      }
      if (snapshot.ready && !_connecting) {
        _connecting = true;
        _ticker?.cancel();
        _ticker = null;
        await ref
            .read(sessionControllerProvider)
            .connectFromPairing(snapshot.pairing!);
        if (!mounted) return;
        context.go('/live');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      _polling = false;
    }
  }

  bool _hasCloudAuth(AppConfig config, SupabaseService supabase) {
    final token = supabase.accessToken;
    if ((token ?? '').trim().isNotEmpty) return true;
    return config.appSharedToken.trim().isNotEmpty;
  }
}

class _CloudFeaturePreview extends StatelessWidget {
  const _CloudFeaturePreview();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cloud surface',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            const _CloudPreviewRow(
              icon: Icons.power_settings_new_rounded,
              label: 'PC-off runner handoff',
            ),
            const _CloudPreviewRow(
              icon: Icons.account_tree_rounded,
              label: 'Git repo clone or encrypted snapshot restore',
            ),
            const _CloudPreviewRow(
              icon: Icons.speed_rounded,
              label: 'Runner size, spend cap, idle shutdown',
            ),
            const _CloudPreviewRow(
              icon: Icons.lock_rounded,
              label: 'Relay stays ciphertext-only',
            ),
          ],
        ),
      ),
    );
  }
}

class _CloudPreviewRow extends StatelessWidget {
  const _CloudPreviewRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudProgressCard extends StatefulWidget {
  const _CloudProgressCard({
    required this.start,
    required this.snapshot,
    required this.startedAt,
    required this.connecting,
  });

  final CloudSessionStartResult start;
  final CloudSessionSnapshot? snapshot;
  final DateTime? startedAt;
  final bool connecting;

  @override
  State<_CloudProgressCard> createState() => _CloudProgressCardState();
}

class _CloudProgressCardState extends State<_CloudProgressCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = widget.snapshot?.status ?? widget.start.status;
    final elapsedSeconds = widget.startedAt == null
        ? 0
        : DateTime.now().difference(widget.startedAt!).inSeconds;
    final progressIndex = _progressIndex(
      status: status,
      elapsedSeconds: elapsedSeconds,
      estimatedSeconds: widget.start.estimatedSeconds,
      connecting: widget.connecting,
    );
    final steps = const [
      'Selecting nearest region',
      'Creating cloud runner',
      'Securing tunnel',
      'Installing daemon',
      'Preparing workspace',
      'Connecting session',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_done_rounded, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Server ${widget.start.serverId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.secondary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.start.message.isEmpty
                  ? 'Provisioning cloud runner.'
                  : widget.start.message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Region: ${widget.start.region} | ${elapsedSeconds}s elapsed',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CloudStepRow(
                  label: steps[i],
                  state: i < progressIndex
                      ? _CloudStepState.done
                      : i == progressIndex
                          ? _CloudStepState.active
                          : _CloudStepState.pending,
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _progressIndex({
    required String status,
    required int elapsedSeconds,
    required int estimatedSeconds,
    required bool connecting,
  }) {
    final value = status.toLowerCase();
    if (connecting) return 5;
    if (value == 'ready') return 5;
    final estimate = estimatedSeconds <= 0 ? 45 : estimatedSeconds;
    final ratio = (elapsedSeconds / estimate).clamp(0.0, 0.95);
    final projected = (ratio * 5).floor();
    if (projected < 0) return 0;
    if (projected > 4) return 4;
    return projected;
  }
}

enum _CloudStepState {
  pending,
  active,
  done,
}

class _CloudStepRow extends StatelessWidget {
  const _CloudStepRow({
    required this.label,
    required this.state,
  });

  final String label;
  final _CloudStepState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (state) {
      _CloudStepState.pending => Icons.radio_button_unchecked_rounded,
      _CloudStepState.active => Icons.autorenew_rounded,
      _CloudStepState.done => Icons.check_circle_rounded,
    };
    final color = switch (state) {
      _CloudStepState.pending => scheme.onSurfaceVariant,
      _CloudStepState.active => scheme.primary,
      _CloudStepState.done => Colors.green.shade600,
    };
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: state == _CloudStepState.pending
                      ? FontWeight.w500
                      : FontWeight.w800,
                ),
          ),
        ),
      ],
    );
  }
}
