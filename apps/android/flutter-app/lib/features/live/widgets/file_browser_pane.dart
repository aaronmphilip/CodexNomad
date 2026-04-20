import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';

class FileBrowserPane extends StatelessWidget {
  const FileBrowserPane({
    super.key,
    required this.controller,
    required this.files,
  });

  final SessionController controller;
  final List<FileEntry> files;

  @override
  Widget build(BuildContext context) {
    final changed = files.where((f) => f.status.trim() != 'tracked').toList();
    final all = files;

    return RefreshIndicator(
      onRefresh: () => controller.requestFiles(),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Changed Files', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (changed.isEmpty)
            const _EmptyFiles(text: 'No changed files reported yet.')
          else
            for (final file in changed) _FileTile(file: file, controller: controller),
          const SizedBox(height: 18),
          Text('Project Files', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (all.isEmpty)
            const _EmptyFiles(text: 'Pull down to request the project tree.')
          else
            for (final file in all) _FileTile(file: file, controller: controller),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({required this.file, required this.controller});

  final FileEntry file;
  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(Icons.description_rounded, color: file.statusColor(scheme)),
        title: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(file.status),
        trailing: IconButton(
          tooltip: 'Open editor',
          onPressed: () => controller.readFile(file.path),
          icon: const Icon(Icons.edit_rounded),
        ),
        onTap: () => controller.readFile(file.path),
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
