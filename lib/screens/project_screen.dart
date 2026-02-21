import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../models/project.dart';
import '../providers/project_provider.dart';
import '../providers/linux_environment_provider.dart';
import 'main_screen.dart';

class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key});
  @override
  State<ProjectScreen> createState() => _ProjectScreenState();
}

class _ProjectScreenState extends State<ProjectScreen> {
  final _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<ProjectProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Import Python file from device',
            onPressed: _importFileFromDevice,
          ),
        ],
      ),
      body: Column(
        children: [
          // Create new project bar
          Container(
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'New project name',
                      hintText: 'my_project',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.code, size: 18),
                    ),
                    onSubmitted: (_) => _createProject(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isCreating ? null : _createProject,
                  child: _isCreating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create'),
                ),
              ],
            ),
          ),

          // Projects list
          Expanded(
            child: provider.projects.isEmpty
                ? _buildEmpty(theme)
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: provider.projects.length,
                    itemBuilder: (ctx, i) {
                      final project = provider.projects[i];
                      final isActive = provider.currentProject?.id == project.id;
                      return _ProjectTile(
                        project: project,
                        isActive: isActive,
                        onTap: () => _openProject(project),
                        onDelete: () => _deleteProject(project),
                        onExport: () => _exportProject(project),
                      ).animate(delay: (i * 40).ms).fadeIn().slideY(begin: 0.1);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 64, color: theme.colorScheme.onSurfaceVariant.withAlpha(100)),
          const SizedBox(height: 16),
          Text('No projects yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Create a project or import a Python file', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _importFileFromDevice,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import .py file'),
          ),
        ],
      ),
    );
  }

  Future<void> _createProject() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a project name')));
      return;
    }

    setState(() => _isCreating = true);
    try {
      await context.read<ProjectProvider>().createProject(name);
      _nameController.clear();
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _openProject(Project project) async {
    await context.read<ProjectProvider>().openProject(project.id);
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    }
  }

  Future<void> _importFileFromDevice() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['py', 'txt', 'json', 'csv', 'md'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) return;

      // Create a project with the imported files
      final firstFile = result.files.first;
      final projectName = path.basenameWithoutExtension(firstFile.name);

      final appDir = await getApplicationSupportDirectory();
      final projectDir = Directory(path.join(appDir.path, 'projects', '${DateTime.now().millisecondsSinceEpoch}_$projectName'));
      await projectDir.create(recursive: true);

      // Copy all selected files to the new project
      for (final file in result.files) {
        if (file.path != null) {
          final dest = File(path.join(projectDir.path, file.name));
          await File(file.path!).copy(dest.path);
        }
      }

      // Load the project
      await context.read<ProjectProvider>().importProjectFromPath(projectDir.path, projectName);
      if (!context.mounted) return;

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Imported \${result.files.length} file(s)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _exportProject(Project project) async {
    try {
      final linuxProvider = context.read<LinuxEnvironmentProvider>();
      final files = project.files.where((f) => f.isPythonFile).toList();
      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No Python files to export')));
        return;
      }

      for (final file in files) {
        await linuxProvider.saveFileToDownloads(file.path, file.name);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Saved ${files.length} file(s) to Downloads/Pyom/')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _deleteProject(Project project) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Delete "${project.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () async {
              await context.read<ProjectProvider>().deleteProject(project.id);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  final Project project;
  final bool isActive;
  final VoidCallback onTap, onDelete, onExport;

  const _ProjectTile({required this.project, required this.isActive, required this.onTap, required this.onDelete, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isActive ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.folder, color: isActive ? theme.colorScheme.onPrimary : theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(project.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${project.files.length} files', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('OPEN', style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'export') onExport();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'export', child: Row(children: [Icon(Icons.download, size: 16), SizedBox(width: 8), Text('Save to Downloads')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
