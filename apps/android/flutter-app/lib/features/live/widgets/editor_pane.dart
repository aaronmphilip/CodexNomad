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
    required this.openFiles,
    required this.openingPath,
    required this.onOpenFile,
    required this.onCloseFile,
  });

  final SessionController controller;
  final CodeFile? file;
  final List<CodeFile> openFiles;
  final String? openingPath;
  final ValueChanged<String> onOpenFile;
  final ValueChanged<String> onCloseFile;

  @override
  State<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<EditorPane> {
  CodeController? _code;
  String? _path;
  String _baseline = '';
  final TextEditingController _find = TextEditingController();
  final TextEditingController _line = TextEditingController();
  List<int> _matches = const [];
  int _matchCursor = -1;
  bool _showSearch = false;

  bool get _isDirty => _code != null && _code!.fullText != _baseline;

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
    _code?.removeListener(_onCodeChanged);
    _code?.dispose();
    _find.dispose();
    _line.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final opening = widget.openingPath;
    if (opening != null && (file == null || file.path != opening)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Opening ${_fileName(opening)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                opening,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    if (file == null || _code == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.code_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              const Text('Open a file from Files.'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _showSearch ? 'Hide search' : 'Find in file',
                onPressed: () {
                  setState(() => _showSearch = !_showSearch);
                  if (_showSearch) {
                    _refreshSearchMatches();
                  }
                },
                icon: Icon(
                  _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
                ),
              ),
              if (_isDirty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Unsaved',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              IconButton(
                tooltip: 'Revert changes',
                onPressed: _isDirty
                    ? () {
                        _code!.text = _baseline;
                        setState(() {});
                      }
                    : null,
                icon: const Icon(Icons.restore_rounded),
              ),
              FilledButton.icon(
                onPressed: _isDirty
                    ? () {
                        final next = _code!.fullText;
                        _baseline = next;
                        setState(() {});
                        widget.controller.saveFile(file.path, next);
                      }
                    : null,
                icon: const Icon(Icons.save_rounded),
                label: Text(_isDirty ? 'Save' : 'Saved'),
              ),
            ],
          ),
        ),
        if (widget.openFiles.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final open in widget.openFiles)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InputChip(
                      selected: open.path == file.path,
                      label: Text(
                        _fileName(open.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => widget.onOpenFile(open.path),
                      onDeleted: () => widget.onCloseFile(open.path),
                    ),
                  ),
              ],
            ),
          ),
        if (_showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _find,
                    onChanged: (_) => _refreshSearchMatches(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.find_in_page_rounded),
                      labelText: 'Find',
                      hintText: 'Search text in this file',
                      suffixText: _matches.isEmpty
                          ? '0'
                          : '${_matchCursor + 1}/${_matches.length}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Previous match',
                  onPressed: _matches.isEmpty ? null : () => _jumpMatch(-1),
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Next match',
                  onPressed: _matches.isEmpty ? null : () => _jumpMatch(1),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _line,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _goToLine(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.format_list_numbered_rounded),
                      hintText: 'Line',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: 'Go to line',
                  onPressed: _goToLine,
                  icon: const Icon(Icons.arrow_right_alt_rounded),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${'\n'.allMatches(_code!.fullText).length + 1} lines | ${_code!.fullText.length} chars',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: CodeTheme(
            data:
                CodeThemeData(styles: dark ? monokaiSublimeTheme : githubTheme),
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
    if (file == null) return;
    if (file.path == _path) {
      if (!_isDirty && _baseline != file.content && _code != null) {
        _baseline = file.content;
        _code!.text = file.content;
        _refreshSearchMatches();
        setState(() {});
      }
      return;
    }
    _path = file.path;
    _baseline = file.content;
    _code?.removeListener(_onCodeChanged);
    _code?.dispose();
    _code = CodeController(
      text: file.content,
      language: _languageFor(file.path),
    )..addListener(_onCodeChanged);
    _refreshSearchMatches();
  }

  void _onCodeChanged() {
    if (_find.text.trim().isNotEmpty) {
      _refreshSearchMatches(preserveCursor: true);
    }
    if (!mounted) return;
    setState(() {});
  }

  void _refreshSearchMatches({bool preserveCursor = false}) {
    final controller = _code;
    final query = _find.text;
    if (controller == null || query.isEmpty) {
      _matches = const [];
      _matchCursor = -1;
      return;
    }
    final text = controller.fullText.toLowerCase();
    final needle = query.toLowerCase();
    final next = <int>[];
    var start = 0;
    while (true) {
      final index = text.indexOf(needle, start);
      if (index < 0) break;
      next.add(index);
      start = index + needle.length;
    }
    _matches = next;
    if (_matches.isEmpty) {
      _matchCursor = -1;
      return;
    }
    if (!preserveCursor ||
        _matchCursor >= _matches.length ||
        _matchCursor < 0) {
      _matchCursor = 0;
      _selectMatch(_matchCursor);
    }
  }

  void _jumpMatch(int delta) {
    if (_matches.isEmpty) return;
    final total = _matches.length;
    _matchCursor = (_matchCursor + delta) % total;
    if (_matchCursor < 0) _matchCursor += total;
    _selectMatch(_matchCursor);
    setState(() {});
  }

  void _selectMatch(int index) {
    final controller = _code;
    if (controller == null ||
        index < 0 ||
        index >= _matches.length ||
        _find.text.isEmpty) {
      return;
    }
    final start = _matches[index];
    final end = start + _find.text.length;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
  }

  void _goToLine() {
    final controller = _code;
    if (controller == null) return;
    final requested = int.tryParse(_line.text.trim());
    if (requested == null || requested < 1) return;
    final text = controller.fullText;
    var line = 1;
    var offset = 0;
    while (offset < text.length && line < requested) {
      if (text.codeUnitAt(offset) == 10) line++;
      offset++;
    }
    if (line != requested) return;
    controller.selection = TextSelection.collapsed(offset: offset);
    setState(() {});
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

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    if (index < 0) return normalized;
    return normalized.substring(index + 1);
  }
}
