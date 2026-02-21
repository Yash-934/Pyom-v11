import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/project.dart';

class ProjectProvider extends ChangeNotifier {
  List<Project>  _projects       = [];
  Project?       _currentProject;
  ProjectFile?   _currentFile;
  bool           _isLoading      = false;
  String?        _errorMessage;

  static const _kProjectsKey = 'projects_v2';
  static const _kLastProject = 'last_project_id';
  static const _kLastFile    = 'last_file_id';

  ProjectProvider() { _initialize(); }

  // ── Getters ──────────────────────────────────────────────────────────────

  List<Project>  get projects       => List.unmodifiable(_projects);
  Project?       get currentProject => _currentProject;
  ProjectFile?   get currentFile    => _currentFile;
  bool           get isLoading      => _isLoading;
  String?        get errorMessage   => _errorMessage;
  bool           get hasOpenProject => _currentProject != null;
  bool           get hasOpenFile    => _currentFile != null;

  // ── Init ─────────────────────────────────────────────────────────────────

  Future<void> _initialize() async {
    _setLoading(true);
    try {
      await _loadProjects();
      await _restoreLastOpen();
    } catch (e) {
      _errorMessage = 'Init error: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_kProjectsKey) ?? [];
    _projects   = raw.map((s) {
      try { return Project.fromJson(jsonDecode(s) as Map<String, dynamic>); }
      catch (_) { return null; }
    }).whereType<Project>().toList();
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kProjectsKey, _projects.map((p) => jsonEncode(p.toJson())).toList());
  }

  Future<void> _restoreLastOpen() async {
    final prefs      = await SharedPreferences.getInstance();
    final lastProjId = prefs.getString(_kLastProject);
    final lastFileId = prefs.getString(_kLastFile);

    if (lastProjId != null) {
      final proj = _projects.where((p) => p.id == lastProjId).firstOrNull;
      if (proj != null) {
        _currentProject = proj;
        await _syncFilesFromDisk(proj);
        if (lastFileId != null) {
          _currentFile = _currentProject!.files.where((f) => f.id == lastFileId).firstOrNull;
          if (_currentFile != null) {
            final content = await File(_currentFile!.path).readAsString().catchError((_) => '');
            _currentFile = _currentFile!.copyWith(content: content);
          }
        }
      }
    }
  }

  Future<void> _syncFilesFromDisk(Project proj) async {
    final dir = Directory(proj.path);
    if (!await dir.exists()) return;
    final onDisk = await dir.list(recursive: true)
        .where((e) => e is File && !p.basename(e.path).startsWith('.'))
        .map((e) => e.path)
        .toList();

    final existing = {for (final f in proj.files) f.path: f};
    final synced   = <ProjectFile>[];

    for (final path in onDisk) {
      if (existing.containsKey(path)) {
        synced.add(existing[path]!);
      } else {
        synced.add(ProjectFile(
          id: const Uuid().v4(),
          name: p.basename(path),
          path: path,
          modifiedAt: await File(path).lastModified().catchError((_) => DateTime.now()),
        ));
      }
    }

    final updated = proj.copyWith(files: synced);
    final idx = _projects.indexWhere((p) => p.id == proj.id);
    if (idx != -1) _projects[idx] = updated;
    _currentProject = updated;
    await _saveProjects();
  }

  Future<void> _persistLastOpen() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentProject != null) { await prefs.setString(_kLastProject, _currentProject!.id); }
    else                         { await prefs.remove(_kLastProject); }
    if (_currentFile != null)    { await prefs.setString(_kLastFile, _currentFile!.id); }
    else                         { await prefs.remove(_kLastFile); }
  }

  // ── Projects ─────────────────────────────────────────────────────────────

  Future<void> createProject(String name) async {
    _setLoading(true);
    try {
      final baseDir    = await getApplicationDocumentsDirectory();
      final projectDir = Directory(p.join(baseDir.path, 'projects', name.replaceAll(' ', '_')));
      await projectDir.create(recursive: true);

      // Create a starter main.py
      final mainPy = File(p.join(projectDir.path, 'main.py'));
      await mainPy.writeAsString('# $name\n\nprint("Hello from $name!")\n');

      final proj = Project(
        id: const Uuid().v4(),
        name: name,
        path: projectDir.path,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
        files: [
          ProjectFile(
            id: const Uuid().v4(),
            name: 'main.py',
            path: mainPy.path,
            content: '# $name\n\nprint("Hello from $name!")\n',
            modifiedAt: DateTime.now(),
          ),
        ],
      );

      _projects.add(proj);
      _currentProject = proj;
      _currentFile    = proj.files.first;
      await _saveProjects();
      await _persistLastOpen();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to create project: $e';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> openProject(String projectId) async {
    final proj = _projects.where((p) => p.id == projectId).firstOrNull;
    if (proj == null) return;
    _currentProject = proj;
    _currentFile    = null;
    await _syncFilesFromDisk(proj);
    await _persistLastOpen();
    notifyListeners();
  }

  Future<void> renameProject(String projectId, String newName) async {
    final idx = _projects.indexWhere((p) => p.id == projectId);
    if (idx == -1) return;
    _projects[idx] = _projects[idx].copyWith(name: newName, modifiedAt: DateTime.now());
    if (_currentProject?.id == projectId) _currentProject = _projects[idx];
    await _saveProjects();
    notifyListeners();
  }

  Future<void> deleteProject(String projectId) async {
    try {
      final proj = _projects.where((p) => p.id == projectId).firstOrNull;
      if (proj == null) return;
      final dir = Directory(proj.path);
      if (await dir.exists()) await dir.delete(recursive: true);
      _projects.removeWhere((p) => p.id == projectId);
      if (_currentProject?.id == projectId) {
        _currentProject = null;
        _currentFile    = null;
      }
      await _saveProjects();
      await _persistLastOpen();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete project: $e';
      notifyListeners();
    }
  }


  // ── Import project from external path (used when user picks files) ────────

  Future<void> importProjectFromPath(String dirPath, String projectName) async {
    _setLoading(true);
    try {
      // Sync files from the temp dir we created in project_screen
      final proj = Project(
        id: const Uuid().v4(),
        name: projectName,
        path: dirPath,
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
      _projects.add(proj);
      _currentProject = proj;
      _currentFile = null;
      await _syncFilesFromDisk(proj);
      await _saveProjects();
      await _persistLastOpen();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to import project: $e';
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  void closeProject() {
    _currentProject = null;
    _currentFile    = null;
    _persistLastOpen();
    notifyListeners();
  }

  // ── Files ────────────────────────────────────────────────────────────────

  Future<void> createFile(String fileName) async {
    if (_currentProject == null) return;
    try {
      final filePath = p.join(_currentProject!.path, fileName);
      await File(filePath).writeAsString('');
      final file = ProjectFile(
        id: const Uuid().v4(), name: fileName, path: filePath, modifiedAt: DateTime.now(), isOpen: true,
      );
      final updatedFiles = [..._currentProject!.files, file];
      _currentProject = _currentProject!.copyWith(files: updatedFiles, modifiedAt: DateTime.now());
      _currentFile    = file;
      final idx = _projects.indexWhere((p) => p.id == _currentProject!.id);
      if (idx != -1) _projects[idx] = _currentProject!;
      await _saveProjects();
      await _persistLastOpen();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to create file: $e';
      notifyListeners();
    }
  }

  Future<void> createFolder(String folderName) async {
    if (_currentProject == null) return;
    try {
      final dir = Directory(p.join(_currentProject!.path, folderName));
      await dir.create(recursive: true);
      // Optional: create a .gitkeep so folder is visible
      await File(p.join(dir.path, '.gitkeep')).writeAsString('');
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to create folder: $e';
      notifyListeners();
    }
  }

  Future<void> openFile(String fileId) async {
    if (_currentProject == null) return;
    final file = _currentProject!.files.where((f) => f.id == fileId).firstOrNull;
    if (file == null) return;
    try {
      final content = await File(file.path).readAsString();
      final opened  = file.copyWith(content: content, isOpen: true, isModified: false);
      final updated = _currentProject!.files.map((f) => f.id == fileId ? opened : f).toList();
      _currentProject = _currentProject!.copyWith(files: updated);
      _currentFile    = opened;
      final idx = _projects.indexWhere((p) => p.id == _currentProject!.id);
      if (idx != -1) _projects[idx] = _currentProject!;
      await _saveProjects();
      await _persistLastOpen();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to open file: $e';
      notifyListeners();
    }
  }

  Future<void> saveFile(String content, {bool silent = false}) async {
    if (_currentFile == null || _currentProject == null) return;
    try {
      await File(_currentFile!.path).writeAsString(content);
      final saved   = _currentFile!.copyWith(content: content, modifiedAt: DateTime.now(), isModified: false);
      final updated = _currentProject!.files.map((f) => f.id == _currentFile!.id ? saved : f).toList();
      _currentProject = _currentProject!.copyWith(files: updated, modifiedAt: DateTime.now());
      _currentFile    = saved;
      final idx = _projects.indexWhere((p) => p.id == _currentProject!.id);
      if (idx != -1) _projects[idx] = _currentProject!;
      await _saveProjects();
      if (!silent) notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to save: $e';
      if (!silent) notifyListeners();
    }
  }

  Future<void> renameFile(String fileId, String newName) async {
    if (_currentProject == null) return;
    try {
      final file    = _currentProject!.files.where((f) => f.id == fileId).firstOrNull;
      if (file == null) return;
      final newPath = p.join(p.dirname(file.path), newName);
      await File(file.path).rename(newPath);
      final renamed = file.copyWith(name: newName, path: newPath, modifiedAt: DateTime.now());
      final updated = _currentProject!.files.map((f) => f.id == fileId ? renamed : f).toList();
      _currentProject = _currentProject!.copyWith(files: updated);
      if (_currentFile?.id == fileId) _currentFile = renamed;
      final idx = _projects.indexWhere((p) => p.id == _currentProject!.id);
      if (idx != -1) _projects[idx] = _currentProject!;
      await _saveProjects();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to rename: $e';
      notifyListeners();
    }
  }

  Future<void> deleteFile(String fileId) async {
    if (_currentProject == null) return;
    try {
      final file = _currentProject!.files.where((f) => f.id == fileId).firstOrNull;
      if (file == null) return;
      final disk = File(file.path);
      if (await disk.exists()) await disk.delete();
      final updated = _currentProject!.files.where((f) => f.id != fileId).toList();
      _currentProject = _currentProject!.copyWith(files: updated);
      if (_currentFile?.id == fileId) {
        _currentFile = updated.where((f) => f.isOpen).lastOrNull;
      }
      final idx = _projects.indexWhere((p) => p.id == _currentProject!.id);
      if (idx != -1) _projects[idx] = _currentProject!;
      await _saveProjects();
      await _persistLastOpen();
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to delete: $e';
      notifyListeners();
    }
  }

  void closeFileTab(String fileId) {
    if (_currentProject == null) return;
    final updated = _currentProject!.files.map((f) => f.id == fileId ? f.copyWith(isOpen: false) : f).toList();
    _currentProject = _currentProject!.copyWith(files: updated);
    if (_currentFile?.id == fileId) {
      _currentFile = updated.where((f) => f.isOpen).lastOrNull;
    }
    final idx = _projects.indexWhere((p) => p.id == _currentProject!.id);
    if (idx != -1) _projects[idx] = _currentProject!;
    _saveProjects();
    _persistLastOpen();
    notifyListeners();
  }

  void markFileModified() {
    if (_currentFile == null || _currentFile!.isModified) return;
    _currentFile = _currentFile!.copyWith(isModified: true);
    notifyListeners();
  }

  void clearError() { _errorMessage = null; notifyListeners(); }

  void _setLoading(bool v) { _isLoading = v; notifyListeners(); }
}
