import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/linux_environment_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
// DATA MODEL
// ════════════════════════════════════════════════════════════════════════════

class LLMModel {
  final String id;
  final String name;
  final String path;
  final String description;
  final int    fileSizeBytes;
  final DateTime addedAt;

  LLMModel({required this.id, required this.name, required this.path,
    this.description = '', this.fileSizeBytes = 0, required this.addedAt});

  String get sizeLabel {
    if (fileSizeBytes <= 0) return 'Unknown size';
    final gb = fileSizeBytes / (1024 * 1024 * 1024);
    final mb = fileSizeBytes / (1024 * 1024);
    return gb >= 1 ? '${gb.toStringAsFixed(1)} GB' : '${mb.toStringAsFixed(0)} MB';
  }

  factory LLMModel.fromJson(Map<String, dynamic> j) => LLMModel(
    id: j['id'] ?? '', name: j['name'] ?? '', path: j['path'] ?? '',
    description: j['description'] ?? '', fileSizeBytes: j['fileSizeBytes'] ?? 0,
    addedAt: DateTime.tryParse(j['addedAt'] ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'path': path, 'description': description,
    'fileSizeBytes': fileSizeBytes, 'addedAt': addedAt.toIso8601String(),
  };
}

// ════════════════════════════════════════════════════════════════════════════
// SCREEN
// ════════════════════════════════════════════════════════════════════════════

class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  List<LLMModel> _models      = [];
  LLMModel?      _activeModel;
  bool           _isRunning   = false;
  bool           _isInstalling = false;
  String         _output      = '';
  String         _installLog  = '';
  int            _maxTokens   = 256;
  double         _temperature = 0.7;
  String         _backend     = 'llama_cpp_python'; // or 'ctransformers'

  final _promptCtrl = TextEditingController();
  static const _kKey = 'llm_models_v3';

  @override
  void initState() { super.initState(); _loadModels(); }

  @override
  void dispose() { _promptCtrl.dispose(); super.dispose(); }

  Future<void> _loadModels() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getStringList(_kKey) ?? [];
      setState(() {
        _models = raw.map((s) {
          try { return LLMModel.fromJson(jsonDecode(s) as Map<String, dynamic>); }
          catch (_) { return null; }
        }).whereType<LLMModel>().toList();
      });
    } catch (_) {}
  }

  Future<void> _saveModels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kKey, _models.map((m) => jsonEncode(m.toJson())).toList());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surface,
      child: Column(children: [
        _buildHeader(theme),
        Expanded(child: _models.isEmpty ? _buildEmpty(theme) : _buildModelList(theme)),
        if (_activeModel != null) _buildInference(theme),
      ]),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(children: [
        Icon(Icons.psychology, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('LLM Models (${_models.length})',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        // Backend selector
        DropdownButton<String>(
          value: _backend,
          underline: const SizedBox.shrink(),
          isDense: true,
          style: theme.textTheme.bodySmall,
          items: const [
            DropdownMenuItem(value: 'llama_cpp_python', child: Text('llama-cpp-python')),
            DropdownMenuItem(value: 'ctransformers',    child: Text('ctransformers')),
          ],
          onChanged: (v) => setState(() => _backend = v!),
        ),
        const SizedBox(width: 4),
        IconButton(icon: const Icon(Icons.help_outline, size: 18), onPressed: _showHelp, tooltip: 'Help'),
        FilledButton.icon(
          onPressed: _importModel,
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Import .gguf'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        ),
      ]),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.psychology_alt_outlined, size: 56, color: theme.colorScheme.onSurfaceVariant.withAlpha(100)),
          const SizedBox(height: 16),
          Text('No models imported', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('Import a .gguf file to run local LLMs on-device',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _importModel, icon: const Icon(Icons.upload_file), label: const Text('Import .gguf Model')),
          const SizedBox(height: 8),
          TextButton(onPressed: _showHelp, child: const Text('Where to get models?')),
        ],
      ),
    );
  }

  Widget _buildModelList(ThemeData theme) {
    return ListView.builder(
      itemCount: _models.length,
      itemBuilder: (_, i) {
        final m       = _models[i];
        final isActive = _activeModel?.id == m.id;
        final exists  = File(m.path).existsSync();
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: isActive ? 3 : 1,
          color: isActive ? theme.colorScheme.primaryContainer.withAlpha(100) : null,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            leading: CircleAvatar(
              backgroundColor: exists
                  ? (isActive ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest)
                  : theme.colorScheme.errorContainer,
              child: Icon(
                exists ? Icons.psychology : Icons.warning_amber,
                size: 20,
                color: exists ? (isActive ? Colors.white : theme.colorScheme.onSurface) : theme.colorScheme.error,
              ),
            ),
            title: Row(children: [
              Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(m.sizeLabel, style: theme.textTheme.labelSmall),
              ),
            ]),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.path, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                if (!exists)
                  Text('⚠ File not found', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (exists)
                  IconButton(
                    icon: Icon(isActive ? Icons.close : Icons.play_arrow, size: 20),
                    tooltip: isActive ? 'Deactivate' : 'Use this model',
                    onPressed: () => setState(() {
                      _activeModel = isActive ? null : m;
                      _output = '';
                    }),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Remove',
                  onPressed: () => _removeModel(m),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INFERENCE PANEL
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildInference(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Model active header
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(Icons.psychology, size: 14, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Active: ${_activeModel!.name}',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Settings
              IconButton(
                icon: const Icon(Icons.tune, size: 16),
                tooltip: 'Generation settings',
                onPressed: _showGenerationSettings,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              // Install backend
              IconButton(
                icon: const Icon(Icons.download, size: 16),
                tooltip: 'Install backend',
                onPressed: _installBackend,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() { _activeModel = null; _output = ''; }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ]),
          ),

          // Install log
          if (_isInstalling)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Text(_installLog.isEmpty ? 'Installing backend…' : _installLog,
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
              ]),
            ),

          // Output area
          if (_output.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _output,
                  style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4,
                      color: _output.startsWith('Error') ? theme.colorScheme.error : null),
                ),
              ),
            ),

          // Input
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _promptCtrl,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'Type your prompt…',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _isRunning
                  ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(strokeWidth: 2))
                  : FilledButton(
                      onPressed: _sendPrompt,
                      style: FilledButton.styleFrom(minimumSize: const Size(40, 40), padding: EdgeInsets.zero),
                      child: const Icon(Icons.send, size: 18),
                    ),
            ]),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _importModel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final ext  = (file.extension ?? '').toLowerCase();
      if (!['gguf', 'bin', 'ggml'].contains(ext)) {
        _snack('⚠ Select a .gguf / .bin / .ggml file');
        return;
      }

      final path   = file.path!;
      final size   = File(path).lengthSync();
      final model  = LLMModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: file.name.replaceAll(RegExp(r'\.(gguf|bin|ggml)$'), ''),
        path: path, fileSizeBytes: size, addedAt: DateTime.now(),
      );
      setState(() => _models.add(model));
      await _saveModels();
      _snack('✅ Model added: ${model.name}');
    } catch (e) {
      _snack('Error: $e');
    }
  }

  void _removeModel(LLMModel m) {
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove Model'),
        content: Text('Remove "${m.name}" from list?\n(The .gguf file will NOT be deleted)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              setState(() { _models.removeWhere((x) => x.id == m.id); if (_activeModel?.id == m.id) _activeModel = null; });
              await _saveModels();
              if (mounted) Navigator.pop(d);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _installBackend() async {
    final linux = context.read<LinuxEnvironmentProvider>();
    if (!linux.isReady) { _snack('Install Linux environment first (Settings)'); return; }

    setState(() { _isInstalling = true; _installLog = 'Installing $_backend…'; });

    try {
      final pkg = _backend == 'ctransformers' ? 'ctransformers' : 'llama-cpp-python';
      final result = await linux.runCommand(
        'pip3 install $pkg --break-system-packages 2>&1 || pip3 install $pkg 2>&1',
        timeoutMs: 300000,
      );
      if (!mounted) return;
      setState(() {
        _installLog = result.isSuccess
            ? '✅ $pkg installed successfully!'
            : 'Error:\n${result.error}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _installLog = 'Error: $e');
    } finally {
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _isInstalling = false);
    }
  }

  Future<void> _sendPrompt() async {
    if (_promptCtrl.text.trim().isEmpty || _activeModel == null) return;
    final prompt = _promptCtrl.text.trim();
    setState(() { _isRunning = true; _output = 'Generating…\n'; });

    final linux = context.read<LinuxEnvironmentProvider>();
    if (!linux.isReady) {
      setState(() { _isRunning = false; _output = 'Error: Linux environment not set up.'; });
      return;
    }

    try {
      final result = await linux.runLlamaModel(
        _activeModel!.path,
        prompt: prompt,
        maxTokens: _maxTokens,
        temperature: _temperature,
        backend: _backend,
      );
      setState(() {
        _isRunning = false;
        _output    = result.isSuccess ? result.output.trim() : 'Error: ${result.error}';
      });
      _promptCtrl.clear();
    } catch (e) {
      setState(() { _isRunning = false; _output = 'Error: $e'; });
    }
  }

  void _showGenerationSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Generation Settings', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(children: [
                const Text('Max tokens:'),
                Expanded(child: Slider(
                  value: _maxTokens.toDouble(),
                  min: 64, max: 1024, divisions: 30,
                  label: '$_maxTokens',
                  onChanged: (v) { setModalState(() => _maxTokens = v.toInt()); setState(() => _maxTokens = v.toInt()); },
                )),
                Text('$_maxTokens', style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              Row(children: [
                const Text('Temperature:'),
                Expanded(child: Slider(
                  value: _temperature, max: 2.0, divisions: 40,
                  label: _temperature.toStringAsFixed(2),
                  onChanged: (v) { setModalState(() => _temperature = v); setState(() => _temperature = v); },
                )),
                Text(_temperature.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Getting GGUF Models'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Best sources for GGUF models:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('1. huggingface.co → Search "GGUF"\n'
                  '   Recommended: TheBloke\'s models\n\n'
                  '2. Recommended small models (work on phones):\n'
                  '   • Phi-2 Q4_K_M (~1.7 GB)\n'
                  '   • TinyLlama Q4_K_M (~0.7 GB)\n'
                  '   • Gemma-2B Q4_K_M (~1.5 GB)\n'
                  '   • Mistral-7B-v0.1 Q2_K (~3 GB — needs 6 GB RAM)\n\n'
                  '3. Download to your phone Downloads folder\n'
                  '4. Tap "Import .gguf" → select file\n\n'
                  'Tip: Q4_K_M is the best quality/size balance.\n'
                  'Avoid Q8 or F16 — too large for mobile.'),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
