import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/all.dart';

import '../providers/project_provider.dart';
import '../providers/editor_provider.dart';

// ── Catppuccin Mocha dark theme ──────────────────────────────────────────────
const Map<String, TextStyle> _kDarkTheme = {
  'root':         TextStyle(backgroundColor: Color(0xFF1E1E2E), color: Color(0xFFCDD6F4)),
  'keyword':      TextStyle(color: Color(0xFFCBA6F7), fontWeight: FontWeight.bold),
  'built_in':     TextStyle(color: Color(0xFF89B4FA)),
  'string':       TextStyle(color: Color(0xFFA6E3A1)),
  'string-2':     TextStyle(color: Color(0xFFA6E3A1)),
  'number':       TextStyle(color: Color(0xFFFAB387)),
  'comment':      TextStyle(color: Color(0xFF6C7086), fontStyle: FontStyle.italic),
  'class':        TextStyle(color: Color(0xFF89DCEB), fontWeight: FontWeight.bold),
  'function':     TextStyle(color: Color(0xFF89B4FA)),
  'title':        TextStyle(color: Color(0xFF89B4FA)),
  'params':       TextStyle(color: Color(0xFFCDD6F4)),
  'literal':      TextStyle(color: Color(0xFFEBA0AC)),
  'type':         TextStyle(color: Color(0xFF89DCEB)),
  'meta':         TextStyle(color: Color(0xFFCBA6F7)),
  'symbol':       TextStyle(color: Color(0xFFF38BA8)),
  'variable':     TextStyle(color: Color(0xFFF5C2E7)),
  'attribute':    TextStyle(color: Color(0xFFFAB387)),
  'regexp':       TextStyle(color: Color(0xFFA6E3A1)),
  'link':         TextStyle(color: Color(0xFF89DCEB), decoration: TextDecoration.underline),
  'operator':     TextStyle(color: Color(0xFF89DCEB)),
  'punctuation':  TextStyle(color: Color(0xFFCDD6F4)),
  'deletion':     TextStyle(color: Color(0xFFF38BA8)),
  'addition':     TextStyle(color: Color(0xFFA6E3A1)),
  'tag':          TextStyle(color: Color(0xFFF38BA8)),
  'attr':         TextStyle(color: Color(0xFFFAB387)),
  'selector-tag': TextStyle(color: Color(0xFFCBA6F7)),
  'formula':      TextStyle(color: Color(0xFFA6E3A1)),
  'subst':        TextStyle(color: Color(0xFFCDD6F4)),
  'section':      TextStyle(color: Color(0xFF89B4FA), fontWeight: FontWeight.bold),
  'bullet':       TextStyle(color: Color(0xFFF38BA8)),
  'code':         TextStyle(color: Color(0xFFA6E3A1), fontFamily: 'monospace'),
  'emphasis':     TextStyle(fontStyle: FontStyle.italic),
  'strong':       TextStyle(fontWeight: FontWeight.bold),
};

// ── Monokai-ish light theme ───────────────────────────────────────────────────
const Map<String, TextStyle> _kLightTheme = {
  'root':         TextStyle(backgroundColor: Color(0xFFFAFAFA), color: Color(0xFF383A42)),
  'keyword':      TextStyle(color: Color(0xFFA626A4), fontWeight: FontWeight.bold),
  'built_in':     TextStyle(color: Color(0xFF4078F2)),
  'string':       TextStyle(color: Color(0xFF50A14F)),
  'string-2':     TextStyle(color: Color(0xFF50A14F)),
  'number':       TextStyle(color: Color(0xFFE45649)),
  'comment':      TextStyle(color: Color(0xFFA0A1A7), fontStyle: FontStyle.italic),
  'class':        TextStyle(color: Color(0xFFC18401), fontWeight: FontWeight.bold),
  'function':     TextStyle(color: Color(0xFF4078F2)),
  'title':        TextStyle(color: Color(0xFF4078F2)),
  'literal':      TextStyle(color: Color(0xFF0184BC)),
  'type':         TextStyle(color: Color(0xFFC18401)),
  'meta':         TextStyle(color: Color(0xFFA626A4)),
  'variable':     TextStyle(color: Color(0xFFE45649)),
  'operator':     TextStyle(color: Color(0xFF0184BC)),
  'punctuation':  TextStyle(color: Color(0xFF383A42)),
  'attr':         TextStyle(color: Color(0xFFC18401)),
};

class CodeEditor extends StatefulWidget {
  const CodeEditor({super.key});

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late CodeController _codeController;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _lineNumberScrollController = ScrollController();

  String? _lastFileId;
  bool _isSyncing = false;
  Timer? _autoSaveTimer;
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    _codeController = CodeController(language: python);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFromProvider();
      context.read<ProjectProvider>().addListener(_onProviderChanged);
    });
    _codeController.addListener(_onTextChanged);
    
    // Sync line number scrolling with code scrolling
    _scrollController.addListener(_syncScroll);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    try { context.read<ProjectProvider>().removeListener(_onProviderChanged); } catch (_) {}
    _scrollController.removeListener(_syncScroll);
    _codeController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _lineNumberScrollController.dispose();
    super.dispose();
  }

  void _syncScroll() {
    if (_lineNumberScrollController.hasClients && _scrollController.hasClients) {
      _lineNumberScrollController.jumpTo(_scrollController.offset);
    }
  }

  void _onProviderChanged() {
    if (!mounted) return;
    final newId = context.read<ProjectProvider>().currentFile?.id;
    if (newId != _lastFileId) _syncFromProvider();
  }

  void _syncFromProvider() {
    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    _lastFileId = provider.currentFile?.id;
    final content = provider.currentFile?.content ?? '';
    final lang    = _langFor(provider.currentFile?.name ?? 'untitled.py');

    _isSyncing = true;
    _codeController.removeListener(_onTextChanged);
    _codeController.dispose();
    _codeController = CodeController(text: content, language: lang);
    _codeController.addListener(_onTextChanged);
    _updateLineCount();
    _isSyncing = false;

    context.read<EditorProvider>().clearHistory();
    if (mounted) setState(() {});
  }

  dynamic _langFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'py':              return python;
      case 'js': case 'ts':  return allLanguages['javascript'];
      case 'json':            return allLanguages['json'];
      case 'sh': case 'bash': return allLanguages['bash'];
      case 'md':              return allLanguages['markdown'];
      case 'yaml': case 'yml': return allLanguages['yaml'];
      case 'html':            return allLanguages['xml'];
      case 'css':             return allLanguages['css'];
      case 'dart':            return allLanguages['dart'];
      default:                return python;
    }
  }

  void _onTextChanged() {
    if (_isSyncing) return;
    _updateLineCount();
    final pp = context.read<ProjectProvider>();
    final ep = context.read<EditorProvider>();
    if (pp.hasOpenFile) {
      pp.markFileModified();
      ep.pushState(_codeController.text);
      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && pp.hasOpenFile) pp.saveFile(_codeController.text, silent: true);
      });
    }
  }

  void _updateLineCount() {
    final text = _codeController.text;
    final newLineCount = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    if (newLineCount != _lineCount) {
      setState(() {
        _lineCount = newLineCount;
      });
    }
  }

  void _saveFile() {
    final pp = context.read<ProjectProvider>();
    if (pp.hasOpenFile) {
      pp.saveFile(_codeController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [Icon(Icons.check, color: Colors.white, size: 16), SizedBox(width: 8), Text('File saved')]),
          duration: Duration(seconds: 1),
          backgroundColor: Color(0xFF40A02B),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme           = Theme.of(context);
    final isDark          = theme.brightness == Brightness.dark;
    final pp              = context.watch<ProjectProvider>();
    final ep              = context.watch<EditorProvider>();

    if (!pp.hasOpenFile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.code_off, size: 64, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text('No file open', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text('Select a file from the explorer', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildToolbar(context, pp, ep, isDark),
        if (ep.isSearching) _buildSearchBar(context, ep),
        Expanded(
          child: KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: (event) {
              if (event is! KeyDownEvent) return;
              final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
              if (ctrl && event.logicalKey == LogicalKeyboardKey.keyS) _saveFile();
              if (ctrl && event.logicalKey == LogicalKeyboardKey.keyF) ep.startSearch();
              if (ctrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
                final undone = ep.undo(_codeController.text);
                if (undone != null) {
                  _codeController.text = undone;
                }
              }
              if (ctrl && event.logicalKey == LogicalKeyboardKey.keyY) {
                final redone = ep.redo(_codeController.text);
                if (redone != null) {
                  _codeController.text = redone;
                }
              }
            },
            child: Row(
              children: [
                // Line numbers gutter - FIXED with dynamic width
                if (ep.showLineNumbers) _buildLineNumbersGutter(isDark, ep.fontSize),
                // Code editor
                Expanded(
                  child: CodeTheme(
                    data: CodeThemeData(styles: isDark ? _kDarkTheme : _kLightTheme),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: CodeField(
                        controller: _codeController,
                        textStyle: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: ep.fontSize,
                          height: 1.5,
                        ),
                        gutterStyle: const GutterStyle(
                          width: 0,  // Hide default gutter, we use custom
                          margin: 0,
                          showErrors: false,
                          showFoldingHandles: false,
                          showLineNumbers: false,
                        ),
                        background: isDark ? const Color(0xFF1E1E2E) : const Color(0xFFFAFAFA),
                        wrap: ep.wordWrap,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Line Numbers Gutter - FIXED with auto-adjustable width ─────────────────
  Widget _buildLineNumbersGutter(bool isDark, double fontSize) {
    // Calculate dynamic width based on line count
    // For 1-9 lines: 1 digit, 10-99: 2 digits, 100-999: 3 digits, etc.
    final digitCount = _lineCount.toString().length;
    final gutterWidth = math.max(32.0, digitCount * fontSize * 0.7 + 16);
    
    return Container(
      width: gutterWidth,
      color: isDark ? const Color(0xFF181825) : const Color(0xFFF0F0F0),
      child: SingleChildScrollView(
        controller: _lineNumberScrollController,
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_lineCount, (index) {
            final lineNumber = index + 1;
            return Container(
              height: fontSize * 1.5,
              padding: const EdgeInsets.only(right: 8, left: 4),
              alignment: Alignment.centerRight,
              child: Text(
                lineNumber.toString(),
                style: TextStyle(
                  color: isDark ? const Color(0xFF6C7086) : Colors.grey,
                  fontSize: fontSize * 0.82,
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(BuildContext context, ProjectProvider pp, EditorProvider ep, bool isDark) {
    final theme = Theme.of(context);
    final file  = pp.currentFile;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181825) : theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 10),
          if (file != null) ...[
            _fileIconWidget(file.name),
            const SizedBox(width: 6),
            Text(
              file.name + (file.isModified ? ' ●' : ''),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: file.isModified ? theme.colorScheme.primary : null,
              ),
            ),
          ],
          const Spacer(),
          // Undo/Redo
          _toolbarBtn(
            Icons.undo,
            'Undo (Ctrl+Z)',
            ep.canUndo ? () {
              final undone = ep.undo(_codeController.text);
              if (undone != null) _codeController.text = undone;
            } : null,
            active: ep.canUndo,
          ),
          _toolbarBtn(
            Icons.redo,
            'Redo (Ctrl+Y)',
            ep.canRedo ? () {
              final redone = ep.redo(_codeController.text);
              if (redone != null) _codeController.text = redone;
            } : null,
            active: ep.canRedo,
          ),
          Container(width: 1, height: 20, color: theme.colorScheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
          // Save
          _toolbarBtn(Icons.save_outlined, 'Save (Ctrl+S)', _saveFile),
          // Search
          _toolbarBtn(Icons.search, 'Find (Ctrl+F)', ep.startSearch),
          // Line numbers toggle
          _toolbarBtn(
            Icons.format_list_numbered,
            'Toggle line numbers',
            ep.toggleLineNumbers,
            active: ep.showLineNumbers,
          ),
          // Word wrap
          _toolbarBtn(
            ep.wordWrap ? Icons.wrap_text : Icons.notes,
            'Toggle word wrap',
            ep.toggleWordWrap,
            active: ep.wordWrap,
          ),
          Container(width: 1, height: 20, color: theme.colorScheme.outlineVariant, margin: const EdgeInsets.symmetric(horizontal: 4)),
          // Font -/+
          _toolbarBtn(Icons.remove, 'Decrease font', () => ep.setFontSize(ep.fontSize - 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text('${ep.fontSize.toInt()}', style: theme.textTheme.labelSmall),
          ),
          _toolbarBtn(Icons.add, 'Increase font', () => ep.setFontSize(ep.fontSize + 1)),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String tooltip, VoidCallback? onPressed, {bool active = false}) {
    return IconButton(
      icon: Icon(icon, size: 16, color: active ? const Color(0xFF89B4FA) : (onPressed == null ? Colors.grey : null)),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      onPressed: onPressed,
    );
  }

  Widget _fileIconWidget(String name) {
    final ext = name.contains('.') ? name.split('.').last : '';
    Color color;
    IconData icon;
    switch (ext) {
      case 'py':   color = Colors.blue; icon = Icons.code;
      case 'json': color = Colors.orange; icon = Icons.data_object;
      case 'md':   color = Colors.green; icon = Icons.description;
      case 'sh':   color = Colors.amber; icon = Icons.terminal;
      default:     color = Colors.grey; icon = Icons.insert_drive_file;
    }
    return Icon(icon, size: 14, color: color);
  }

  // ── Search bar ────────────────────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context, EditorProvider ep) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Find…',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search, size: 16),
                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              ),
              onChanged: ep.setSearchQuery,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Replace…',
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(icon: const Icon(Icons.close, size: 16), onPressed: ep.stopSearch, tooltip: 'Close'),
        ],
      ),
    );
  }
}
