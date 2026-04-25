import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WorkspaceToolsPane extends StatefulWidget {
  const WorkspaceToolsPane({
    super.key,
    required this.state,
    required this.controller,
  });

  final LiveSessionState state;
  final SessionController controller;

  @override
  State<WorkspaceToolsPane> createState() => _WorkspaceToolsPaneState();
}

class _WorkspaceToolsPaneState extends State<WorkspaceToolsPane> {
  final _url = TextEditingController();
  late final WebViewController _web;
  bool _loading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _currentUrl = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            _currentUrl = url;
            setState(() {
              _loading = true;
              _error = null;
            });
            _syncNavState();
          },
          onPageFinished: (url) {
            _currentUrl = url;
            setState(() => _loading = false);
            _syncNavState();
          },
          onWebResourceError: (error) => setState(() {
            _loading = false;
            _error = error.description;
          }),
        ),
      );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.requestWorkspaceTools();
      _load(_bestInitialUrl(widget.state.tools));
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceToolsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_url.text.trim().isEmpty) {
      final next = _bestInitialUrl(widget.state.tools);
      if (next.isNotEmpty) _url.text = next;
    }
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tools = widget.state.tools;
    return RefreshIndicator(
      onRefresh: widget.controller.requestWorkspaceTools,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          _Header(
            root: widget.state.workspaceRoot,
            loading: widget.state.loadingTools,
            onRefresh: widget.controller.requestWorkspaceTools,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    icon: Icons.public_rounded,
                    title: 'Browser',
                    action: IconButton(
                      tooltip: 'Reload preview',
                      onPressed: () => _load(_url.text),
                      icon: const Icon(PhosphorIconsRegular.arrowClockwise),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _canGoBack ? _goBack : null,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      IconButton(
                        tooltip: 'Forward',
                        onPressed: _canGoForward ? _goForward : null,
                        icon: const Icon(Icons.arrow_forward_rounded),
                      ),
                      IconButton(
                        tooltip: 'Reload',
                        onPressed: () => _load(_url.text),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      Expanded(
                        child: Text(
                          _currentUrl.trim().isEmpty
                              ? _url.text.trim()
                              : _currentUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          onSubmitted: _load,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(PhosphorIconsRegular.link),
                            hintText: 'http://localhost:3000',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Open preview',
                        onPressed: () => _load(_url.text),
                        icon: const Icon(PhosphorIconsRegular.arrowRight),
                      ),
                    ],
                  ),
                  if (tools.ports.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final port in tools.ports.take(8))
                          ActionChip(
                            avatar: const Icon(
                              Icons.cable_rounded,
                              size: 16,
                            ),
                            label: Text('${port.port}'),
                            onPressed:
                                port.url.isEmpty ? null : () => _load(port.url),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 420,
                      decoration: BoxDecoration(
                        color: const Color(0xFF05020A),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Stack(
                        children: [
                          WebViewWidget(controller: _web),
                          if (_loading)
                            LinearProgressIndicator(
                              minHeight: 2,
                              color: scheme.primary,
                            ),
                          if (_error != null)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                width: double.infinity,
                                color: scheme.error.withValues(alpha: 0.14),
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  _error!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: scheme.error),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _GitCard(
            git: tools.git,
            controller: widget.controller,
            inFlightAction: widget.state.gitActionInFlight,
          ),
          const SizedBox(height: 12),
          _PortsCard(ports: tools.ports, onOpen: _load),
          const SizedBox(height: 12),
          _PreviewDevtoolsCard(preview: tools.preview, onOpen: _load),
        ],
      ),
    );
  }

  void _load(String value) {
    final uri = _normalizeUrl(value);
    if (uri == null) return;
    final normalized = uri.toString();
    _url.text = normalized;
    _currentUrl = normalized;
    _web.loadRequest(uri);
    _syncNavState();
  }

  Future<void> _goBack() async {
    if (!await _web.canGoBack()) return;
    await _web.goBack();
    _syncNavState();
  }

  Future<void> _goForward() async {
    if (!await _web.canGoForward()) return;
    await _web.goForward();
    _syncNavState();
  }

  Future<void> _syncNavState() async {
    final back = await _web.canGoBack();
    final forward = await _web.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = back;
      _canGoForward = forward;
    });
  }

  Uri? _normalizeUrl(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    final withScheme = raw.contains('://') ? raw : 'http://$raw';
    return Uri.tryParse(withScheme);
  }

  String _bestInitialUrl(WorkspaceToolsSnapshot tools) {
    if (tools.previewUrl.isNotEmpty) return tools.previewUrl;
    for (final port in tools.ports) {
      if (port.url.isNotEmpty) return port.url;
    }
    return 'http://localhost:3000';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.root,
    required this.loading,
    required this.onRefresh,
  });

  final String root;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: scheme.primary.withValues(alpha: 0.16),
          ),
          child: Icon(Icons.dashboard_customize_rounded, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workspace',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Text(
                root.isEmpty ? 'Waiting for project path' : root,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh tools',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              : const Icon(PhosphorIconsRegular.arrowClockwise),
        ),
      ],
    );
  }
}

class _GitCard extends StatefulWidget {
  const _GitCard({
    required this.git,
    required this.controller,
    required this.inFlightAction,
  });

  final GitSummary git;
  final SessionController controller;
  final String? inFlightAction;

  @override
  State<_GitCard> createState() => _GitCardState();
}

class _GitCardState extends State<_GitCard> {
  final TextEditingController _commit = TextEditingController();
  final TextEditingController _branch = TextEditingController();

  @override
  void dispose() {
    _commit.dispose();
    _branch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final git = widget.git;
    final busyAction = widget.inFlightAction?.trim();
    final isBusy = busyAction != null && busyAction.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: PhosphorIconsRegular.gitBranch,
              title: 'Git',
              action: isBusy
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            if (!git.hasRepo)
              Text(
                'No Git repository detected.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    icon: PhosphorIconsRegular.gitBranch,
                    label: git.branch,
                  ),
                  if (git.remote.isNotEmpty)
                    _MetaChip(
                      icon: PhosphorIconsRegular.cloud,
                      label: git.remote,
                    ),
                  if (git.ahead > 0)
                    _MetaChip(
                      icon: PhosphorIconsRegular.arrowUp,
                      label: '${git.ahead} ahead',
                    ),
                  if (git.behind > 0)
                    _MetaChip(
                      icon: PhosphorIconsRegular.arrowDown,
                      label: '${git.behind} behind',
                    ),
                ],
              ),
              if (git.lastCommit.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  git.lastCommit,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => _run('stage_all'),
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text('Stage all'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => _run('unstage_all'),
                    icon: const Icon(Icons.remove_done_rounded),
                    label: const Text('Unstage'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => _run('pull'),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Pull'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: isBusy ? null : () => _run('push'),
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Push'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _commit,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.message_rounded),
                  labelText: 'Commit message',
                  hintText: 'fix: improve mobile reconnect flow',
                ),
              ),
              if (git.branches.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final branchName in git.branches.take(14))
                      ActionChip(
                        avatar: Icon(
                          branchName == git.branch
                              ? Icons.check_circle_rounded
                              : Icons.alt_route_rounded,
                          size: 16,
                        ),
                        label: Text(branchName),
                        onPressed: isBusy || branchName == git.branch
                            ? null
                            : () {
                                _branch.text = branchName;
                                _run('checkout', branch: branchName);
                              },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _branch,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.alt_route_rounded),
                        labelText: 'Checkout branch',
                        hintText: 'main',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: isBusy || _branch.text.trim().isEmpty
                        ? null
                        : () => _run(
                              'checkout',
                              branch: _branch.text,
                            ),
                    child: const Text('Switch'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: isBusy || _commit.text.trim().isEmpty
                      ? null
                      : () => _run(
                            'commit',
                            message: _commit.text,
                          ),
                  icon: const Icon(Icons.done_all_rounded),
                  label: Text(
                    busyAction == 'commit' ? 'Committing...' : 'Commit',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${git.changed.length} changed files',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              if (git.changed.isEmpty)
                Text(
                  'Working tree clean.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                )
              else
                for (final file in git.changed.take(12))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          child: Text(
                            file.status,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: file.statusColor(scheme),
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            file.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _run(
    String action, {
    String? message,
    String? branch,
  }) {
    return widget.controller.runGitAction(
      action,
      message: message,
      branch: branch,
    );
  }
}

class _PortsCard extends StatelessWidget {
  const _PortsCard({required this.ports, required this.onOpen});

  final List<PortEntry> ports;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              icon: Icons.cable_rounded,
              title: 'Ports',
            ),
            const SizedBox(height: 10),
            if (ports.isEmpty)
              Text(
                'No listening dev ports found.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else
              for (final port in ports.take(24))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: port.url.isEmpty ? null : () => onOpen(port.url),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: scheme.primary.withValues(alpha: 0.12),
                            ),
                            child: Center(
                              child: Text(
                                '${port.port}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: scheme.secondary,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  port.process.isEmpty
                                      ? port.protocol.toUpperCase()
                                      : port.process,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  port.url.isEmpty
                                      ? '${port.address} pid ${port.pid}'
                                      : port.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                                if (port.directUrl.isNotEmpty &&
                                    port.directUrl != port.url)
                                  Text(
                                    'direct: ${port.directUrl}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant
                                              .withValues(alpha: 0.78),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.open_in_new_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _PreviewDevtoolsCard extends StatelessWidget {
  const _PreviewDevtoolsCard({
    required this.preview,
    required this.onOpen,
  });

  final PreviewInspector preview;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              icon: Icons.developer_mode_rounded,
              title: 'Devtools',
              action: IconButton(
                tooltip: 'Open proxy base',
                onPressed: preview.proxyUrl.isEmpty
                    ? null
                    : () => onOpen(preview.proxyUrl),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(
                  icon: preview.enabled
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  label: preview.enabled ? 'Proxy online' : 'Proxy offline',
                ),
                _MetaChip(
                  icon: Icons.http_rounded,
                  label: '${preview.recentRequests.length} recent requests',
                ),
              ],
            ),
            if (preview.proxyUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                preview.proxyUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            if (preview.recentRequests.isEmpty)
              Text(
                'No preview traffic yet.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              )
            else
              for (final entry in preview.recentRequests.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: scheme.surface.withValues(alpha: 0.42),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              entry.method,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${entry.status}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(
                                    color: _statusColor(entry.status, scheme),
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '${entry.durationMs} ms',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.path.isEmpty ? '/' : entry.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                        if (entry.error.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            entry.error,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: scheme.error,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(int status, ColorScheme scheme) {
    if (status >= 500) return scheme.error;
    if (status >= 400) return Colors.orange.shade700;
    if (status >= 200) return Colors.green.shade600;
    return scheme.onSurfaceVariant;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.secondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.secondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}
