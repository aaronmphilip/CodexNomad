import 'package:codex_nomad/features/home/session_card.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionControllerProvider).recentSessions;
    final auth = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex Nomad'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/scan'),
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text('New Session'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          children: [
            _HeroPanel(onScan: () => context.push('/scan')),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Active Sessions', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: sessions.isEmpty ? scheme.outline : Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.laptop_mac_rounded, color: scheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'No paired sessions yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Run codexnomad codex or codexnomad claude, then scan the terminal QR.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...sessions.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SessionCard(summary: s),
                  )),
            const SizedBox(height: 22),
            if (!auth.configured)
              _AuthNudge(
                text: 'Supabase auth is not configured. Local sessions still work.',
                icon: Icons.info_outline_rounded,
              )
            else if (!auth.signedIn)
              _AuthNudge(
                text: 'Sign in from Settings to sync session history.',
                icon: Icons.lock_open_rounded,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primaryContainer.withOpacity(0.38),
        border: Border.all(color: scheme.primary.withOpacity(0.16)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Control Codex and Claude Code from your phone',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Live terminal, approvals, diffs, and quick file edits without babysitting your desk.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Scan QR Code'),
          ),
        ],
      ),
    );
  }
}

class _AuthNudge extends StatelessWidget {
  const _AuthNudge({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
