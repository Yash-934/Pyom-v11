import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/project_provider.dart';
import '../models/project.dart';
import '../screens/project_screen.dart';

class FileExplorer extends StatelessWidget {
  final Function(ProjectFile)? onFileSelected;
  const FileExplorer({super.key, this.onFileSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pp    = context.watch<ProjectProvider>();

    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context, theme, pp),
          Expanded(
            child: pp.hasOpenProject
                ? _buildFileTree(context, pp)
                : _buildNoProject(context, theme),
          ),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, ThemeData theme, ProjectProvider pp) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
        border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              pp.hasOpenProject ? pp.currentProject!.name : 'EXPLORER',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pp.hasOpenProject) ...[
            _hdrBtn(context, Icons.add, 'New File',   () => _newFileDialog(context)),
            _hdrBtn(context, Icons.create_new_folder_outlined, 'New Folder', () => _newFolderDialog(context)),
            _hdrBtn(context, Icons.more_vert, 'Project options', () => _projectMenu(context, pp)),
          ],
        ],
      ),
    );
  }

  Widget _hdrBtn(BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 17),
      tooltip: tip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onTap,
    );
  }

  // ── No project ─────────────────────────────────────────────────────────────

  Widget _buildNoProject(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(100)),
          const SizedBox(height: 12),
          Text('No project open', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Open / Create Project'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProjectScreen())),
          ),
        ],
      ),
    );
  }

  // ── File tree ───────────────────────────────────────────────────────────────

  Widget _buildFileTree(BuildContext context, ProjectProvider pp) {
    final project    = pp.currentProject!;
    final projectDir = project.path;

    // Group files by immediate subdirectory (1 level deep)
    final Map<String, List<ProjectFile>> byFolder = {};
    final List<ProjectFile> rootFiles             = [];

    for (final f in project.files) {
      final rel = _relative(f.path, projectDir);
      final sep = Platform.pathSeparator;
      final idx = rel.indexOf(sep);
      if (idx > 0) {
        final folder = rel.substring(0, idx);
        byFolder.putIfAbsent(folder, () => []).add(f);
      } else {
        rootFiles.add(f);
      }
    }

    final items = <Widget>[];

    // Folders first (sorted)
    for (final folder in (byFolder.keys.toList()..sort())) {
      items.add(_FolderItem(
        name: folder,
        files: byFolder[folder]!,
        currentFileId: pp.currentFile?.id,
        onFileTap: (f) { pp.openFile(f.id); onFileSelected?.call(f); },
        onFileRename: (f) => _renameFileDialog(context, f),
        onFileDelete: (f) => _deleteFileDialog(context, f),
        onFolderDelete: () => _deleteFolderDialog(context, pp, folder, byFolder[folder]!),
      ));
    }

    // Root files
    for (final f in rootFiles) {
      items.add(_FileItem(
        file: f,
        isSelected: pp.currentFile?.id == f.id,
        depth: 0,
        onTap: () { pp.openFile(f.id); onFileSelected?.call(f); },
        onRename: () => _renameFileDialog(context, f),
        onDelete: () => _deleteFileDialog(context, f),
      ));
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insert_drive_file_outlined, size: 36, color: Colors.grey.withAlpha(150)),
              const SizedBox(height: 8),
              const Text('No files yet', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New File'),
                onPressed: () => _newFileDialog(context),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: items);
  }

  String _relative(String filePath, String projectPath) {
    if (filePath.startsWith(projectPath)) {
      var rel = filePath.substring(projectPath.length);
      if (rel.startsWith(Platform.pathSeparator)) rel = rel.substring(1);
      return rel;
    }
    return filePath.split(Platform.pathSeparator).last;
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  void _newFileDialog(BuildContext context) {
    _inputDialog(context, title: 'New File', hint: 'example.py', label: 'File name', onConfirm: (name) {
      context.read<ProjectProvider>().createFile(name);
    });
  }

  void _newFolderDialog(BuildContext context) {
    _inputDialog(context, title: 'New Folder', hint: 'my_module', label: 'Folder name', onConfirm: (name) {
      context.read<ProjectProvider>().createFolder(name);
    });
  }

  void _renameFileDialog(BuildContext context, ProjectFile file) {
    _inputDialog(context, title: 'Rename File', label: 'New name', initial: file.name, onConfirm: (name) {
      context.read<ProjectProvider>().renameFile(file.id, name);
    });
  }

  void _deleteFileDialog(BuildContext context, ProjectFile file) {
    _confirmDialog(
      context,
      title: 'Delete File',
      body: 'Delete "${file.name}"?\nThis cannot be undone.',
      onConfirm: () => context.read<ProjectProvider>().deleteFile(file.id),
    );
  }

  void _deleteFolderDialog(BuildContext context, ProjectProvider pp, String folder, List<ProjectFile> files) {
    _confirmDialog(
      context,
      title: 'Delete Folder',
      body: 'Delete "$folder" and all ${files.length} file(s) inside?\nThis cannot be undone.',
      onConfirm: () { for (final f in files) { pp.deleteFile(f.id); } },
    );
  }

  // ── Project options bottom sheet ─────────────────────────────────────────────

  void _projectMenu(BuildContext context, ProjectProvider pp) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (modal) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Open Different Project'),
              onTap: () {
                Navigator.pop(modal);
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProjectScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename Project'),
              onTap: () {
                Navigator.pop(modal);
                _inputDialog(context, title: 'Rename Project', label: 'New name',
                    initial: pp.currentProject?.name ?? '', onConfirm: (name) {
                  if (pp.currentProject != null) pp.renameProject(pp.currentProject!.id, name);
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close Project'),
              onTap: () { pp.closeProject(); Navigator.pop(modal); },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
              title: Text('Delete Project Permanently', style: TextStyle(color: theme.colorScheme.error)),
              onTap: () {
                Navigator.pop(modal);
                _confirmDialog(context,
                  title: 'Delete Project',
                  body: 'Delete "${pp.currentProject?.name}" and ALL files from disk?\nThis CANNOT be undone.',
                  onConfirm: () { if (pp.currentProject != null) pp.deleteProject(pp.currentProject!.id); },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Generic dialog helpers ────────────────────────────────────────────────────

  void _inputDialog(BuildContext context, {
    required String title,
    required String label,
    String hint = '',
    String initial = '',
    required Function(String) onConfirm,
  }) {
    final ctrl = TextEditingController(text: initial);
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (v) { if (v.isNotEmpty) { onConfirm(v); Navigator.pop(d); } },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () { if (ctrl.text.isNotEmpty) { onConfirm(ctrl.text); Navigator.pop(d); } },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _confirmDialog(BuildContext context, {
    required String title,
    required String body,
    required VoidCallback onConfirm,
    bool destructive = true,
  }) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () { onConfirm(); Navigator.pop(d); },
            style: destructive ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error) : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FOLDER ITEM — collapsible
// ══════════════════════════════════════════════════════════════════════════════

class _FolderItem extends StatefulWidget {
  final String name;
  final List<ProjectFile> files;
  final String? currentFileId;
  final Function(ProjectFile) onFileTap;
  final Function(ProjectFile) onFileRename;
  final Function(ProjectFile) onFileDelete;
  final VoidCallback onFolderDelete;

  const _FolderItem({
    required this.name, required this.files, required this.currentFileId,
    required this.onFileTap, required this.onFileRename,
    required this.onFileDelete, required this.onFolderDelete,
  });

  @override
  State<_FolderItem> createState() => _FolderItemState();
}

class _FolderItemState extends State<_FolderItem> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          onLongPress: () => _folderContextMenu(context),
          child: Container(
            height: 28,
            padding: const EdgeInsets.only(left: 6, right: 4),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 2),
                Icon(_open ? Icons.folder_open : Icons.folder, size: 16, color: Colors.amber.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(widget.name,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  onPressed: widget.onFolderDelete,
                  icon: Icon(Icons.delete_outline, size: 14, color: theme.colorScheme.error),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  tooltip: 'Delete folder',
                ),
              ],
            ),
          ),
        ),
        if (_open)
          ...widget.files.map((f) => _FileItem(
            file: f,
            isSelected: widget.currentFileId == f.id,
            depth: 1,
            onTap: () => widget.onFileTap(f),
            onRename: () => widget.onFileRename(f),
            onDelete: () => widget.onFileDelete(f),
          )),
      ],
    );
  }

  void _folderContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (m) => SafeArea(
        child: ListTile(
          leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
          title: Text('Delete "${widget.name}" and contents', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () { Navigator.pop(m); widget.onFolderDelete(); },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FILE ITEM
// ══════════════════════════════════════════════════════════════════════════════

class _FileItem extends StatelessWidget {
  final ProjectFile file;
  final bool isSelected;
  final int depth;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FileItem({
    required this.file, required this.isSelected, required this.depth,
    required this.onTap, required this.onRename, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: () => _contextMenu(context),
      child: Container(
        height: 28,
        padding: EdgeInsets.only(left: 10.0 + depth * 16, right: 4),
        color: isSelected ? theme.colorScheme.primaryContainer : Colors.transparent,
        child: Row(
          children: [
            _icon(theme),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                file.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (file.isModified)
              Container(
                width: 6, height: 6, margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: isSelected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _icon(ThemeData theme) {
    Color c;
    IconData i;
    switch (file.extension) {
      case 'py':   c = Colors.blue; i = Icons.code;
      case 'md':   c = Colors.green; i = Icons.description;
      case 'json': c = Colors.orange; i = Icons.data_object;
      case 'txt':  c = Colors.grey; i = Icons.text_snippet;
      case 'yaml': case 'yml': c = Colors.purple; i = Icons.settings;
      case 'sh':   c = Colors.amber; i = Icons.terminal;
      default:     c = theme.colorScheme.onSurfaceVariant; i = Icons.insert_drive_file;
    }
    return Icon(i, size: 15, color: isSelected ? theme.colorScheme.onPrimaryContainer : c);
  }

  void _contextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (m) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename'),
              onTap: () { Navigator.pop(m); onRename(); },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.error),
              title: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () { Navigator.pop(m); onDelete(); },
            ),
          ],
        ),
      ),
    );
  }
}
