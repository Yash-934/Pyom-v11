import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/project_provider.dart';
import '../providers/linux_environment_provider.dart';
import '../providers/editor_provider.dart';
import '../widgets/file_explorer.dart';
import '../widgets/code_editor.dart';
import '../widgets/terminal_panel.dart';
import '../widgets/output_panel.dart';
import 'project_screen.dart';
import 'settings_screen.dart';
import 'package_manager_screen.dart';
import 'model_manager_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int    _selectedIndex  = 0;
  bool   _showOutput     = false;
  bool   _showTerminal   = false;
  double _outputHeight   = 200;
  double _terminalHeight = 200;
  
  late AnimationController _fabAnimationController;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      return constraints.maxWidth >= 720
          ? _buildDesktop(context)
          : _buildMobile(context);
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LAYOUTS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDesktop(BuildContext context) {
    final theme = Theme.of(context);
    final pp    = context.watch<ProjectProvider>();

    return Scaffold(
      body: Row(children: [
        // ── Nav rail ──
        NavigationRail(
          minWidth: 60,
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) =>
              i == 4 ? _showSettings() : setState(() => _selectedIndex = i),
          labelType: NavigationRailLabelType.all,
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: Text('Explorer')),
            NavigationRailDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: Text('Search')),
            NavigationRailDestination(icon: Icon(Icons.extension_outlined), selectedIcon: Icon(Icons.extension), label: Text('Packages')),
            NavigationRailDestination(icon: Icon(Icons.psychology_outlined), selectedIcon: Icon(Icons.psychology), label: Text('Models')),
          ],
          trailing: Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _showSettings),
              ),
            ),
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          child: Column(children: [
            _buildTabBar(theme, pp),
            Expanded(
              child: Row(children: [
                if (_selectedIndex == 0) ...[
                  const SizedBox(width: 240, child: FileExplorer()),
                  const VerticalDivider(thickness: 1, width: 1),
                ],
                Expanded(child: Column(children: [
                  Expanded(child: pp.hasOpenFile ? const CodeEditor() : _buildEmptyState(context)),
                  if (_showOutput)   _buildResizablePanel(isOutput: true),
                  if (_showTerminal) _buildResizablePanel(isOutput: false),
                ])),
                if (_selectedIndex == 2) const SizedBox(width: 300, child: PackageManagerScreen()),
                if (_selectedIndex == 3) const SizedBox(width: 340, child: ModelManagerScreen()),
              ]),
            ),
            _buildStatusBar(context),
          ]),
        ),
      ]),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final theme = Theme.of(context);
    final pp    = context.watch<ProjectProvider>();

    return Scaffold(
      key: _scaffoldKey,
      // ── Drawer with file explorer ──
      drawer: Drawer(
        width: 280,
        child: SafeArea(
          child: Column(children: [
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
              ),
              child: Row(children: [
                Icon(Icons.code, color: theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 10),
                Text('Pyom IDE', style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
              ]),
            ),
            const Expanded(child: FileExplorer()),
            // Bottom actions in drawer
            const Divider(height: 1),
            _drawerAction(context, Icons.extension_outlined, 'Package Manager', () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackageManagerScreen()));
            }),
            _drawerAction(context, Icons.psychology_outlined, 'LLM Models', () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModelManagerScreen()));
            }),
            _drawerAction(context, Icons.settings_outlined, 'Settings', () {
              Navigator.pop(context);
              _showSettings();
            }),
            const SizedBox(height: 8),
          ]),
        ),
      ),
      // ── AppBar ──
      appBar: AppBar(
        title: Text(pp.currentProject?.name ?? 'Pyom', overflow: TextOverflow.ellipsis),
        actions: [
          // Quick actions
          if (pp.hasOpenFile) ...[
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save File (Ctrl+S)',
              onPressed: () => _saveCurrentFile(context),
            ),
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded),
              tooltip: 'Run (F5)',
              onPressed: () => _runCurrentFile(context),
            ),
          ],
          // Toggle output/terminal
          IconButton(
            icon: Icon(_showOutput ? Icons.terminal : Icons.terminal_outlined),
            tooltip: 'Toggle Output',
            onPressed: () => setState(() => _showOutput = !_showOutput),
          ),
          // More menu
          PopupMenuButton<String>(
            onSelected: _onMenuSelected,
            itemBuilder: (_) => [
              if (pp.hasOpenFile) ...[
                const PopupMenuItem(value: 'save',     child: _MenuItem(Icons.save, 'Save')),
                const PopupMenuItem(value: 'download', child: _MenuItem(Icons.download, 'Save to Downloads')),
                const PopupMenuItem(value: 'share',    child: _MenuItem(Icons.share, 'Share File')),
                const PopupMenuDivider(),
              ],
              const PopupMenuItem(value: 'terminal', child: _MenuItem(Icons.terminal, 'Toggle Terminal')),
              const PopupMenuItem(value: 'packages', child: _MenuItem(Icons.extension, 'Package Manager')),
              const PopupMenuItem(value: 'models',   child: _MenuItem(Icons.psychology, 'LLM Models')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'settings', child: _MenuItem(Icons.settings, 'Settings')),
              const PopupMenuItem(value: 'projects', child: _MenuItem(Icons.folder, 'Switch Project')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        _buildTabBar(theme, pp),
        Expanded(child: pp.hasOpenFile ? const CodeEditor() : _buildEmptyState(context)),
        if (_showOutput)   _buildResizablePanel(isOutput: true),
        if (_showTerminal) _buildResizablePanel(isOutput: false),
        _buildStatusBar(context),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB BAR (open files)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTabBar(ThemeData theme, ProjectProvider pp) {
    final openFiles = pp.currentProject?.files.where((f) => f.isOpen).toList() ?? [];
    if (openFiles.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: openFiles.length,
        itemBuilder: (ctx, i) {
          final f        = openFiles[i];
          final isActive = f.id == pp.currentFile?.id;
          return InkWell(
            onTap: () => pp.openFile(f.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isActive ? theme.colorScheme.primaryContainer.withAlpha(120) : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? theme.colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(f.isPythonFile ? Icons.code : Icons.description, size: 13,
                    color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Text(
                    f.name + (f.isModified ? ' ●' : ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      color: f.isModified ? theme.colorScheme.primary : null,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => pp.closeFileTab(f.id),
                    borderRadius: BorderRadius.circular(10),
                    child: Icon(Icons.close, size: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RESIZABLE PANELS (output / terminal)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildResizablePanel({required bool isOutput}) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onVerticalDragUpdate: (d) {
          setState(() {
            if (isOutput) {
              _outputHeight   = (_outputHeight   - d.delta.dy).clamp(60.0, 400.0);
            } else {
              _terminalHeight = (_terminalHeight - d.delta.dy).clamp(80.0, 450.0);
            }
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeRow,
          child: Container(
            height: 6,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Container(
              width: 40, height: 3,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
      SizedBox(
        height: isOutput ? _outputHeight : _terminalHeight,
        child: isOutput
            ? OutputPanel(onClose: () => setState(() => _showOutput = false))
            : TerminalPanel(onClose: () => setState(() => _showTerminal = false)),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATUS BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStatusBar(BuildContext context) {
    final theme       = Theme.of(context);
    final linux       = context.watch<LinuxEnvironmentProvider>();
    final pp          = context.watch<ProjectProvider>();
    final pythonVer   = linux.currentEnvironment?.metadata['python_version'] as String? ?? '3.x';

    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)),
      ),
      child: Row(children: [
        // Environment status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: linux.isReady 
                ? Colors.green.withOpacity(0.15) 
                : theme.colorScheme.error.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(linux.isReady ? Icons.check_circle : Icons.error_outline,
                  size: 10, 
                  color: linux.isReady ? Colors.green : theme.colorScheme.error),
              const SizedBox(width: 4),
              Text(linux.isReady ? 'Python $pythonVer' : 'No environment',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: linux.isReady ? Colors.green : theme.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
        if (pp.hasOpenFile) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insert_drive_file, size: 10, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(pp.currentFile!.name, 
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.primary,
                    )),
              ],
            ),
          ),
        ],
        const Spacer(),
        if (linux.isReady) ...[
          // CPU usage
          _buildStatusItem(Icons.memory, 'CPU ${linux.stats.cpuUsage.toStringAsFixed(0)}%', theme),
          const SizedBox(width: 12),
          // Memory usage
          _buildStatusItem(Icons.storage, 'MEM ${linux.stats.memoryUsage.toStringAsFixed(0)}%', theme),
        ],
        const SizedBox(width: 8),
        // Line/column indicator
        if (pp.hasOpenFile)
          Text('Ln ${pp.currentFile?.content.split('\n').length ?? 1}', 
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
      ]),
    );
  }

  Widget _buildStatusItem(IconData icon, String text, ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final pp    = context.watch<ProjectProvider>();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            pp.hasOpenProject ? Icons.code_off : Icons.folder_open,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
          ),
          const SizedBox(height: 16),
          Text(
            pp.hasOpenProject ? 'Select a file to edit' : 'No project open',
            style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            pp.hasOpenProject ? 'Open a file from the sidebar' : 'Create or open a project to start coding',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant.withAlpha(150)),
          ),
          const SizedBox(height: 24),
          if (!pp.hasOpenProject)
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Open / Create Project'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProjectScreen())),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DRAWER HELPER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _drawerAction(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      onTap: onTap,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────────────────────────

  void _onMenuSelected(String value) {
    switch (value) {
      case 'save':     _saveCurrentFile(context);
      case 'download': _saveToDownloads(context);
      case 'share':    _shareCurrentFile(context);
      case 'terminal': setState(() => _showTerminal = !_showTerminal);
      case 'packages':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PackageManagerScreen()));
      case 'models':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ModelManagerScreen()));
      case 'settings': _showSettings();
      case 'projects':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProjectScreen()));
    }
  }

  Future<void> _saveCurrentFile(BuildContext context) async {
    final pp = context.read<ProjectProvider>();
    if (!pp.hasOpenFile) return;
    await pp.saveFile(pp.currentFile!.content);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(children: [Icon(Icons.check, color: Colors.white, size: 16), SizedBox(width: 8), Text('File saved')]),
        duration: Duration(seconds: 1),
        backgroundColor: Color(0xFF40A02B),
      ),
    );
  }

  Future<void> _saveToDownloads(BuildContext context) async {
    final pp    = context.read<ProjectProvider>();
    final linux = context.read<LinuxEnvironmentProvider>();
    if (!pp.hasOpenFile) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No file open')));
      return;
    }
    await pp.saveFile(pp.currentFile!.content);
    try {
      final path = await linux.saveFileToDownloads(pp.currentFile!.path, pp.currentFile!.name);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Saved to $path'), duration: const Duration(seconds: 3)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _shareCurrentFile(BuildContext context) async {
    final pp = context.read<ProjectProvider>();
    if (!pp.hasOpenFile) return;
    final filePath = pp.currentFile!.path;
    await pp.saveFile(pp.currentFile!.content);
    if (!context.mounted) return;
    try {
      await context.read<LinuxEnvironmentProvider>().shareFile(filePath);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText('File path: $filePath')),
      );
    }
  }

  Future<void> _runCurrentFile(BuildContext context) async {
    final pp    = context.read<ProjectProvider>();
    final linux = context.read<LinuxEnvironmentProvider>();
    final ep    = context.read<EditorProvider>();

    if (!pp.hasOpenFile) {
      _snack(context, 'No file open');
      return;
    }
    if (!pp.currentFile!.isPythonFile) {
      _snack(context, 'Only .py files can be run');
      return;
    }
    if (!linux.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Environment not set up → Settings → Install Environment'),
        action: SnackBarAction(label: 'Setup', onPressed: _showSettings),
      ));
      return;
    }

    await pp.saveFile(pp.currentFile!.content);
    setState(() => _showOutput = true);

    ep.startExecution();
    final result = await linux.executePythonCode(pp.currentFile!.content);
    ep.setExecutionResult(output: result.output, error: result.error, executionTime: result.executionTime);
  }

  void _showSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── Simple popup menu row ─────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuItem(this.icon, this.label);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16),
    const SizedBox(width: 10),
    Text(label),
  ]);
}
