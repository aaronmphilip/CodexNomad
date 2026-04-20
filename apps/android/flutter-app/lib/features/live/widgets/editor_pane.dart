import 'package:codex_nomad/models/session_models.dart';
import 'package:codex_nomad/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/go.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/typescript.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

class EditorPane extends StatefulWidget {
  const EditorPane({
    super.key,
    required this.controller,
    required this.file,
  });

  final SessionController controller;
  final CodeFile? file;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  CodeController? _code;
  String? _path;

  @override
  void didUpdateWidget(covariant EditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void dispose() {
    _code?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if (file == null || _code == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.code_rounded, size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              const Text('Open a file from the Files tab to edit it.'),
            ],
          ),
        ),
      );
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  file.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () => widget.controller.saveFile(file.path, _code!.fullText),
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save & Push'),
              ),
            ],
          ),
        ),
        Expanded(
          child: CodeTheme(
            data: CodeThemeData(styles: dark ? monokaiSublimeTheme : githubTheme),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: CodeField(
                controller: _code!,
                gutterStyle: const GutterStyle(
                  showErrors: false,
                  showFoldingHandles: true,
                  showLineNumbers: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _syncController() {
    final file = widget.file;
    if (file == null || file.path == _path) return;
    _path = file.path;
    _code?.dispose();
    _code = CodeController(
      text: file.content,
      language: _languageFor(file.path),
    );
  }

  dynamic _languageFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return dart;
    if (lower.endsWith('.go')) return go;
    if (lower.endsWith('.py')) return python;
    if (lower.endsWith('.ts') || lower.endsWith('.tsx')) return typescript;
    if (lower.endsWith('.js') || lower.endsWith('.jsx')) return javascript;
    if (lower.endsWith('.json')) return json;
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return yaml;
    if (lower.endsWith('.xml') || lower.endsWith('.html')) return xml;
    return dart;
  }
}
