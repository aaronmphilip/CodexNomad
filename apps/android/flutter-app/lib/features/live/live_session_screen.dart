import 'package:codex_nomad/features/live/widgets/chat_pane.dart';
import 'package:codex_nomad/features/live/widgets/editor_pane.dart';
import 'package:codex_nomad/features/live/widgets/file_browser_pane.dart';
import 'package:codex_nomad/features/live/widgets/review_pane.dart';
import 'package:codex_nomad/features/live/widgets/terminal_pane.dart';
import 'package:codex_nomad/features/live/widgets/workspace_tools_pane.dart';
import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:codex_nomad/widgets/brand_mark.dart';
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
    final sessions = controller.recentSessions;
    final currentSessionId = controller.currentSessionId;

    return Scaffold(
      drawer: _ChatDrawer(
        sessions: sessions,
        currentWorkspace: state.workspaceRoot,
        onStartNew: () => context.go('/start'),
        onOpenSession: (id) async {
          await controller.openHistory(id);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
      appBar: AppBar(
        toolbarHeight: state.workspaceRoot.isEmpty ? null : 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_titleFor(state),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            if (state.workspaceRoot.isNotEmpty)
              Text(
                state.workspaceRoot,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
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
            _StatusStrip(
              status: state.status,
              error: state.error,
              activity: state.agentActivity,
              reconnecting: state.status == ConnectionStatus.connecting &&
                  (state.agentActivity?.toLowerCase().contains('reconnect') ??
                      false),
              onReconnect: _canReconnect(state, controller)
                  ? () async {
                      final ok = await ref
                          .read(sessionControllerProvider)
                          .reconnectLastPairing();
                      if (!context.mounted || ok) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Reconnect failed. Start a fresh local session on desktop.',
                          ),
                        ),
                      );
                    }
                  : null,
            ),
            if (sessions.length > 1)
              _QuickSwitchBar(
                sessions: sessions,
                currentSessionId: currentSessionId,
                onSelect: (sessionId) async {
                  await controller.openHistory(sessionId);
                },
              ),
            Expanded(child: _bodyForTab(_tab, state, controller)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
          if (value == 3) controller.requestFiles();
          if (value == 5) controller.requestWorkspaceTools();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.command),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.terminal),
            label: 'Terminal',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.shieldCheck),
            label: 'Review',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.folderOpen),
            label: 'Files',
          ),
          NavigationDestination(
            icon: Icon(PhosphorIconsRegular.code),
            label: 'Editor',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_customize_rounded),
            label: 'Tools',
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
        return ReviewPane(state: state, controller: controller);
      case 3:
        return FileBrowserPane(
          controller: controller,
          files: state.files,
          loading: state.loadingFiles,
          workspaceRoot: state.workspaceRoot,
          onOpenEditor: () => setState(() => _tab = 4),
        );
      case 4:
        return EditorPane(
          controller: controller,
          file: state.openFile,
          openFiles: state.openFiles,
          openingPath: state.openingFilePath,
          onOpenFile: controller.switchOpenFile,
          onCloseFile: controller.closeOpenFile,
        );
      case 5:
        return WorkspaceToolsPane(state: state, controller: controller);
      default:
        return ChatPane(controller: controller, state: state);
    }
  }

  String _titleFor(LiveSessionState state) {
    final workspace = _workspaceName(state.workspaceRoot);
    if (workspace.isNotEmpty) return workspace;
    return state.pairing?.agent.label ?? 'Workspace';
  }

  String _workspaceName(String root) {
    final value = root.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '';
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return value;
    return parts.last;
  }

  bool _canReconnect(LiveSessionState state, SessionController controller) {
    if (controller.lastPairing == null) return false;
    return state.status == ConnectionStatus.disconnected ||
        state.status == ConnectionStatus.error ||
        state.status == ConnectionStatus.ended;
  }
}

class _QuickSwitchBar extends StatelessWidget {
  const _QuickSwitchBar({
    required this.sessions,
    required this.currentSessionId,
    required this.onSelect,
  });

  final List<SessionSummary> sessions;
  final String? currentSessionId;
  final Future<void> Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        scrollDirection: Axis.horizontal,
        children: [
          for (final session in sessions.take(8))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: session.id == currentSessionId,
                label: Text(
                  session.title.isEmpty
                      ? _workspaceName(session.workspaceRoot)
                      : session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                avatar: Icon(
                  session.id == currentSessionId
                      ? Icons.radio_button_checked_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 16,
                  color: session.id == currentSessionId
                      ? Colors.green
                      : scheme.onSurfaceVariant,
                ),
                onSelected: (selected) {
                  if (!selected || session.id == currentSessionId) return;
                  onSelect(session.id);
                },
              ),
            ),
        ],
      ),
    );
  }

  static String _workspaceName(String root) {
    final value = root.trim().replaceAll('\\', '/');
    if (value.isEmpty) return 'Chat';
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? value : parts.last;
  }
}

class _ChatDrawer extends StatefulWidget {
  const _ChatDrawer({
    required this.sessions,
    required this.currentWorkspace,
    required this.onStartNew,
    required this.onOpenSession,
  });

  final List<SessionSummary> sessions;
  final String currentWorkspace;
  final VoidCallback onStartNew;
  final Future<void> Function(String id) onOpenSession;

  @override
  State<_ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends State<_ChatDrawer> {
  final TextEditingController _search = TextEditingController();
  String? _selectedProjectKey;

  @override
  void initState() {
    super.initState();
    _selectedProjectKey = _projectKeyForWorkspace(widget.currentWorkspace);
  }

  @override
  void didUpdateWidget(covariant _ChatDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentWorkspace != widget.currentWorkspace &&
        widget.currentWorkspace.trim().isNotEmpty) {
      _selectedProjectKey = _projectKeyForWorkspace(widget.currentWorkspace);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final projects = _buildProjects(widget.sessions);
    final filteredProjects = projects
        .where((project) => _matchesQuery(project.searchText, query))
        .toList();
    final selectedKey = _selectedProjectKey;
    final chats = widget.sessions.where((session) {
      if (selectedKey != null &&
          _projectKeyForSession(session) != selectedKey) {
        return false;
      }
      final haystack = [
        session.title,
        session.workspaceRoot,
        session.machineName,
        session.agent.label,
      ].join(' ').toLowerCase();
      return _matchesQuery(haystack, query);
    }).toList();

    return Drawer(
      backgroundColor: scheme.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            const Row(
              children: [
                CodexNomadMark(size: 34, showFrame: false),
                SizedBox(width: 10),
                Text(
                  'Workspace',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: widget.onStartNew,
              icon: const Text(
                '</',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              label: const Text('New chat'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.onStartNew,
              icon: const Icon(PhosphorIconsRegular.folderOpen),
              label: const Text('New project'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                hintText: 'Search projects and chats',
              ),
            ),
            const SizedBox(height: 16),
            _DrawerSectionHeader(
              title: 'Projects',
              trailing: '${filteredProjects.length}',
            ),
            const SizedBox(height: 8),
            if (filteredProjects.isEmpty)
              _DrawerHint(
                text: widget.sessions.isEmpty
                    ? 'No saved projects yet.'
                    : 'No projects match your search.',
              )
            else
              for (final project in filteredProjects)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DrawerTile(
                    title: project.name,
                    subtitle:
                        '${project.path}\n${project.chatCount} chats | ${_timeAgo(project.lastActivity)}',
                    selected: project.key == selectedKey,
                    icon: project.key == selectedKey
                        ? PhosphorIconsRegular.checkCircle
                        : PhosphorIconsRegular.folderOpen,
                    onTap: () {
                      setState(() => _selectedProjectKey = project.key);
                      widget.onOpenSession(project.latestSessionId);
                    },
                  ),
                ),
            const SizedBox(height: 14),
            _DrawerSectionHeader(
              title: 'Chats',
              trailing: '${chats.length}',
            ),
            const SizedBox(height: 8),
            if (chats.isEmpty)
              _DrawerHint(
                text: selectedKey == null
                    ? 'No chats yet for this search.'
                    : 'No chats in selected project.',
              )
            else
              for (final session in chats)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DrawerTile(
                    title: session.title.isEmpty
                        ? _workspaceName(session.workspaceRoot)
                        : session.title,
                    subtitle:
                        '${session.workspaceRoot.isEmpty ? session.machineName : session.workspaceRoot}\n${_timeAgo(session.lastActivity)}',
                    selected:
                        session.workspaceRoot == widget.currentWorkspace &&
                            widget.currentWorkspace.isNotEmpty,
                    icon: PhosphorIconsRegular.command,
                    onTap: () => widget.onOpenSession(session.id),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  List<_ProjectSummary> _buildProjects(List<SessionSummary> sessions) {
    final byKey = <String, _ProjectSummary>{};
    for (final session in sessions) {
      final key = _projectKeyForSession(session);
      final name = _workspaceName(session.workspaceRoot);
      final path = session.workspaceRoot.isEmpty
          ? session.machineName
          : session.workspaceRoot;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = _ProjectSummary(
          key: key,
          name: name,
          path: path,
          latestSessionId: session.id,
          chatCount: 1,
          lastActivity: session.lastActivity,
          searchText: '$name $path ${session.machineName}'.toLowerCase(),
        );
        continue;
      }
      byKey[key] = existing.copyWith(
        chatCount: existing.chatCount + 1,
        latestSessionId: session.lastActivity.isAfter(existing.lastActivity)
            ? session.id
            : existing.latestSessionId,
        lastActivity: session.lastActivity.isAfter(existing.lastActivity)
            ? session.lastActivity
            : existing.lastActivity,
      );
    }
    final projects = byKey.values.toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    if (_selectedProjectKey != null &&
        !projects.any((item) => item.key == _selectedProjectKey)) {
      _selectedProjectKey = null;
    }
    return projects;
  }

  bool _matchesQuery(String value, String query) {
    if (query.isEmpty) return true;
    return value.contains(query);
  }

  String _workspaceName(String root) {
    final value = root.trim().replaceAll('\\', '/');
    if (value.isEmpty) return 'Workspace';
    final parts = value.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return value;
    return parts.last;
  }

  String _projectKeyForSession(SessionSummary session) {
    return _projectKeyForWorkspace(session.workspaceRoot, session.machineName);
  }

  String _projectKeyForWorkspace(String workspace, [String machine = '']) {
    final normalized = workspace.trim().replaceAll('\\', '/').toLowerCase();
    if (normalized.isNotEmpty) return 'workspace:$normalized';
    return 'machine:${machine.trim().toLowerCase()}';
  }

  String _timeAgo(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

class _DrawerSectionHeader extends StatelessWidget {
  const _DrawerSectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const Spacer(),
        Text(
          trailing,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _DrawerHint extends StatelessWidget {
  const _DrawerHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      tileColor: selected
          ? scheme.primary.withValues(alpha: 0.16)
          : scheme.primary.withValues(alpha: 0.08),
      leading: Icon(
        icon,
        color: selected ? Colors.green : scheme.primary,
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class _ProjectSummary {
  const _ProjectSummary({
    required this.key,
    required this.name,
    required this.path,
    required this.latestSessionId,
    required this.chatCount,
    required this.lastActivity,
    required this.searchText,
  });

  final String key;
  final String name;
  final String path;
  final String latestSessionId;
  final int chatCount;
  final DateTime lastActivity;
  final String searchText;

  _ProjectSummary copyWith({
    String? latestSessionId,
    int? chatCount,
    DateTime? lastActivity,
  }) {
    return _ProjectSummary(
      key: key,
      name: name,
      path: path,
      latestSessionId: latestSessionId ?? this.latestSessionId,
      chatCount: chatCount ?? this.chatCount,
      lastActivity: lastActivity ?? this.lastActivity,
      searchText: searchText,
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    required this.status,
    this.error,
    this.activity,
    this.onReconnect,
    this.reconnecting = false,
  });

  final ConnectionStatus status;
  final String? error;
  final String? activity;
  final Future<void> Function()? onReconnect;
  final bool reconnecting;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (status) {
      ConnectionStatus.idle => 'Idle',
      ConnectionStatus.pairing => 'Pairing',
      ConnectionStatus.connecting => 'Connecting',
      ConnectionStatus.ready => 'Live',
      ConnectionStatus.disconnected => 'Disconnected',
      ConnectionStatus.ended => 'Ended',
      ConnectionStatus.error => error ?? 'Error',
    };
    final color = switch (status) {
      ConnectionStatus.ready => Colors.green,
      ConnectionStatus.error => scheme.error,
      ConnectionStatus.disconnected => Colors.amber,
      _ => scheme.primary,
    };
    final detail = error?.trim().isNotEmpty == true
        ? error!.trim()
        : activity?.trim().isNotEmpty == true
            ? activity!.trim()
            : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (onReconnect != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: reconnecting ? null : onReconnect,
              icon: reconnecting
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.primary,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(reconnecting ? 'Reconnecting' : 'Reconnect'),
            ),
          ],
        ],
      ),
    );
  }
}
