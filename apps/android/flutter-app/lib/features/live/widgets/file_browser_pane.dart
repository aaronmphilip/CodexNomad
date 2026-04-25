import 'dart:async';

import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class FileBrowserPane extends StatefulWidget {
  const FileBrowserPane({
    super.key,
    required this.controller,
    required this.files,
    required this.loading,
    required this.workspaceRoot,
    required this.onOpenEditor,
  });

  final SessionController controller;
  final List<FileEntry> files;
  final bool loading;
  final String workspaceRoot;
  final VoidCallback onOpenEditor;

  @override
  State<FileBrowserPane> createState() => _FileBrowserPaneState();
}

class _FileBrowserPaneState extends State<FileBrowserPane> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matching = query.isEmpty
        ? widget.files
        : widget.files.where((file) {
            final haystack =
                '${file.name} ${file.path} ${file.status}'.toLowerCase();
            return haystack.contains(query);
          }).toList();
    final changed =
        matching.where((f) => f.status.trim() != 'tracked').toList();

    return RefreshIndicator(
      onRefresh: () => widget.controller.requestFiles(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          _WorkspaceHeader(
            root: widget.workspaceRoot,
            fileCount: widget.files.length,
            changedCount:
                widget.files.where((f) => f.status.trim() != 'tracked').length,
            loading: widget.loading,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass),
                    hintText: 'Search files',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Create file',
                onPressed: _showCreateFileDialog,
                icon: const Icon(Icons.note_add_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Create folder',
                onPressed: _showCreateFolderDialog,
                icon: const Icon(Icons.create_new_folder_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Refresh files',
                onPressed: widget.controller.requestFiles,
                icon: widget.loading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (query.isNotEmpty)
            Text(
              'Search: "$query"',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          if (query.isNotEmpty) const SizedBox(height: 10),
          _SectionTitle(title: 'Changed files', count: changed.length),
          const SizedBox(height: 8),
          if (changed.isEmpty)
            const _EmptyFiles(text: 'No changed files match.')
          else
            for (final file in changed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FileTile(
                  file: file,
                  onOpen: () => _open(file),
                  onRename: () => _showRenameFileDialog(file),
                  onDelete: () => _confirmDelete(file),
                ),
              ),
          const SizedBox(height: 18),
          _SectionTitle(title: 'Project files', count: matching.length),
          const SizedBox(height: 8),
          if (matching.isEmpty)
            _EmptyFiles(
              text: widget.loading
                  ? 'Loading project files...'
                  : widget.files.isEmpty
                      ? 'Pull down to request the project tree.'
                      : 'No files match that search.',
            )
          else
            for (final file in matching)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FileTile(
                  file: file,
                  onOpen: () => _open(file),
                  onRename: () => _showRenameFileDialog(file),
                  onDelete: () => _confirmDelete(file),
                ),
              ),
        ],
      ),
    );
  }

  void _open(FileEntry file) {
    widget.onOpenEditor();
    unawaited(widget.controller.switchOpenFile(file.path));
  }

  Future<void> _showCreateFileDialog() async {
    final path = TextEditingController();
    final content = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create file'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: path,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Relative path',
                    hintText: 'src/new_file.dart',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: content,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Initial content',
                    hintText: '// start coding',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (created != true) {
      path.dispose();
      content.dispose();
      return;
    }
    final rel = path.text.trim();
    final body = content.text;
    path.dispose();
    content.dispose();
    if (rel.isEmpty) return;
    widget.onOpenEditor();
    await widget.controller.saveFile(rel, body);
    await widget.controller.requestFiles();
    await widget.controller.readFile(rel);
  }

  Future<void> _showCreateFolderDialog() async {
    final path = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create folder'),
          content: TextField(
            controller: path,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Relative folder path',
              hintText: 'src/components',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    if (created != true) {
      path.dispose();
      return;
    }
    final rel = path.text.trim();
    path.dispose();
    if (rel.isEmpty) return;
    await widget.controller.createFolder(rel);
    await widget.controller.requestFiles();
  }

  Future<void> _showRenameFileDialog(FileEntry file) async {
    final next = TextEditingController(text: file.path);
    final renamed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename file'),
          content: TextField(
            controller: next,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'New path',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
    if (renamed != true) {
      next.dispose();
      return;
    }
    final path = next.text.trim();
    next.dispose();
    if (path.isEmpty || path == file.path) return;
    await widget.controller.renameFile(file.path, path);
    await widget.controller.requestFiles();
    await widget.controller.readFile(path);
    widget.onOpenEditor();
  }

  Future<void> _confirmDelete(FileEntry file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete file'),
          content: Text(
            'Delete ${file.path}?',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await widget.controller.deleteFile(file.path);
    await widget.controller.requestFiles();
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.root,
    required this.fileCount,
    required this.changedCount,
    required this.loading,
  });

  final String root;
  final int fileCount;
  final int changedCount;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.primary.withValues(alpha: 0.10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.folderOpen, color: scheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _workspaceName(root),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  root.isEmpty ? 'Waiting for project path...' : root,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (loading) const _MetaChip(label: 'Loading...'),
                    _MetaChip(label: '$fileCount files'),
                    _MetaChip(label: '$changedCount changed'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _workspaceName(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return 'Project files';
    final parts =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? normalized : parts.last;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const Spacer(),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final FileEntry file;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: file.statusColor(scheme).withValues(alpha: 0.14),
                ),
                child: Icon(
                  _iconFor(file.name),
                  color: file.statusColor(scheme),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name.isEmpty ? file.path : file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      file.path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _MetaChip(label: file.status),
                        if (file.size != null)
                          _MetaChip(label: _size(file.size!)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open editor',
                onPressed: onOpen,
                icon: const Icon(Icons.edit_rounded),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Text('Rename'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return PhosphorIconsRegular.fileCode;
    if (lower.endsWith('.go')) return PhosphorIconsRegular.fileCode;
    if (lower.endsWith('.json')) return PhosphorIconsRegular.bracketsCurly;
    if (lower.endsWith('.md')) return PhosphorIconsRegular.fileText;
    return PhosphorIconsRegular.file;
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: scheme.surface.withValues(alpha: 0.52),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text),
      ),
    );
  }
}
