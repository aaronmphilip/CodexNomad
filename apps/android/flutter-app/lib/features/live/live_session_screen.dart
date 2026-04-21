import 'package:codex_nomad/features/live/widgets/chat_pane.dart';
import 'package:codex_nomad/features/live/widgets/editor_pane.dart';
import 'package:codex_nomad/features/live/widgets/file_browser_pane.dart';
import 'package:codex_nomad/features/live/widgets/review_pane.dart';
import 'package:codex_nomad/features/live/widgets/session_action_bar.dart';
import 'package:codex_nomad/features/live/widgets/terminal_pane.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/metric_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionControllerProvider);
    final state = controller.state;
    final pairing = state.pairing;

    return Scaffold(
      appBar: AppBar(
        title: Text(pairing?.agent.label ?? 'Live Session'),
        actions: [
          if (pairing != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: MetricChip(
                  icon: pairing.mode == 'cloud'
                      ? Icons.cloud_done_rounded
                      : Icons.laptop_rounded,
                  label: pairing.mode,
                ),
              ),
            ),
          IconButton(
            tooltip: 'End Session',
            onPressed: () async {
              await ref.read(sessionControllerProvider).end();
              if (context.mounted) context.go('/');
            },
            icon: const Icon(PhosphorIconsRegular.xCircle),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StatusStrip(status: state.status, error: state.error),
            SessionActionBar(controller: controller),
            Expanded(child: _bodyForTab(_tab, state, controller)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
          if (value == 3) controller.requestFiles();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.shieldCheck),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.terminal),
            label: 'Terminal',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.command),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.folderOpen),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.code),
            label: 'Editor',
          ),
        ],
      ),
    );
  }

  Widget _bodyForTab(
    int tab,
    LiveSessionState state,
    SessionController controller,
  ) {
    switch (tab) {
      case 1:
        return TerminalPane(state: state, controller: controller);
      case 2:
        return ChatPane(controller: controller, state: state);
      case 3:
        return FileBrowserPane(controller: controller, files: state.files);
      case 4:
        return EditorPane(controller: controller, file: state.openFile);
      default:
        return ReviewPane(state: state, controller: controller);
    }
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.status, this.error});

  final ConnectionStatus status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (status) {
      ConnectionStatus.idle => 'Idle',
      ConnectionStatus.pairing => 'Pairing',
      ConnectionStatus.connecting => 'Connecting',
      ConnectionStatus.ready => 'Live',
      ConnectionStatus.disconnected => 'Reconnecting needed',
      ConnectionStatus.ended => 'Ended',
      ConnectionStatus.error => error ?? 'Error',
    };
    final color = switch (status) {
      ConnectionStatus.ready => Colors.green,
      ConnectionStatus.error => scheme.error,
      ConnectionStatus.disconnected => Colors.amber,
      _ => scheme.primary,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error == null || status == ConnectionStatus.ready
                  ? label
                  : '$label: $error',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
