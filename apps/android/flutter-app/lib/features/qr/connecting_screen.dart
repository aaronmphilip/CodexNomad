import 'dart:async';

import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ConnectingScreen extends ConsumerStatefulWidget {
  const ConnectingScreen({super.key, required this.rawQr});

  final String? rawQr;

  @override
  ConsumerState<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<ConnectingScreen> {
  Timer? _watcher;
  bool _started = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  @override
  void dispose() {
    _watcher?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionControllerProvider).state;
    final scheme = Theme.of(context).colorScheme;
    final connected = _connected || state.status == ConnectionStatus.ready;
    final error =
        _error ?? (state.status == ConnectionStatus.error ? state.error : null);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(child: CodexNomadMark(size: 104, showFrame: false)),
              const SizedBox(height: 28),
              Text(
                connected ? 'Connected' : 'Connecting',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 0.98,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                connected
                    ? 'Opening your workspace.'
                    : 'Pairing this phone with the local agent session.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 26),
              _ConnectionStep(
                icon: PhosphorIconsRegular.qrCode,
                title: 'Code scanned',
                done: widget.rawQr != null,
              ),
              const SizedBox(height: 10),
              _ConnectionStep(
                icon: PhosphorIconsRegular.lockKey,
                title: 'Encrypted channel',
                done: state.status == ConnectionStatus.connecting ||
                    state.status == ConnectionStatus.ready,
              ),
              const SizedBox(height: 10),
              _ConnectionStep(
                icon: PhosphorIconsRegular.terminalWindow,
                title: 'Agent ready',
                done: connected,
              ),
              if (error != null) ...[
                const SizedBox(height: 18),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                      ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.go('/scan'),
                  icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                  label: const Text('Scan again'),
                ),
              ],
              const Spacer(),
              if (!connected && error == null)
                Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: scheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _connect() async {
    if (_started) return;
    _started = true;
    final raw = widget.rawQr;
    if (raw == null || raw.isEmpty) {
      setState(() => _error = 'No pairing code was scanned.');
      return;
    }
    try {
      await ref.read(sessionControllerProvider).connectFromQr(raw);
      _watcher = Timer.periodic(const Duration(milliseconds: 180), (timer) {
        final status = ref.read(sessionControllerProvider).state.status;
        if (status == ConnectionStatus.ready) {
          timer.cancel();
          if (!mounted) return;
          setState(() => _connected = true);
          Future<void>.delayed(const Duration(milliseconds: 520), () {
            if (mounted) context.go('/live');
          });
        }
        if (status == ConnectionStatus.error) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _error = ref.read(sessionControllerProvider).state.error ??
                'Connection failed.';
          });
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }
}

class _ConnectionStep extends StatelessWidget {
  const _ConnectionStep({
    required this.icon,
    required this.title,
    required this.done,
  });

  final IconData icon;
  final String title;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: done ? 0.12 : 0.05),
        border: Border.all(
          color: done
              ? scheme.primary.withValues(alpha: 0.36)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          Icon(
            done
                ? PhosphorIconsRegular.checkCircle
                : PhosphorIconsRegular.circle,
            color: color,
          ),
        ],
      ),
    );
  }
}
