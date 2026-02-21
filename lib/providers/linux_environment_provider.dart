import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/linux_environment.dart';
import '../services/linux_environment_service.dart';
import '../models/python_package.dart';
import '../models/execution_result.dart';

class LinuxEnvironmentProvider extends ChangeNotifier {
  final LinuxEnvironmentService _service;
  final Completer<void> _initCompleter = Completer<void>();

  LinuxEnvironment? _currentEnvironment;
  EnvironmentStatus _status = EnvironmentStatus.notInstalled;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  String? _errorMessage;
  EnvironmentStats _stats = EnvironmentStats.empty();
  List<PythonPackage> _installedPackages = [];
  bool _isLoading = false;

  StreamSubscription? _statsSubscription;
  StreamSubscription? _progressSubscription;

  // SharedPreferences keys
  static const _kLastEnvId = 'last_env_id';
  static const _kLastDistro = 'last_distro';
  static const _kEnvInstalled = 'env_installed';

  LinuxEnvironmentProvider(this._service) {
    _initialize();
  }

  Future<void> get initialized => _initCompleter.future;
  LinuxEnvironment? get currentEnvironment => _currentEnvironment;
  EnvironmentStatus get status => _status;
  double get downloadProgress => _downloadProgress;
  String get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  EnvironmentStats get stats => _stats;
  List<PythonPackage> get installedPackages => _installedPackages;
  bool get isLoading => _isLoading;
  bool get isReady => _status == EnvironmentStatus.ready;
  bool get hasError => _errorMessage != null;

  String get statusDisplay {
    if (_statusMessage.isNotEmpty && _status == EnvironmentStatus.downloading) return _statusMessage;
    switch (_status) {
      case EnvironmentStatus.notInstalled: return 'Not Installed';
      case EnvironmentStatus.downloading:  return 'Downloading…';
      case EnvironmentStatus.installing:   return 'Installing…';
      case EnvironmentStatus.ready:        return 'Ready';
      case EnvironmentStatus.error:        return 'Error';
      default:                             return 'Unknown';
    }
  }

  Future<void> _initialize() async {
    _statsSubscription    = _service.statsStream.listen((s)    { _stats = s; notifyListeners(); });
    _progressSubscription = _service.progressStream.listen((p) {
      _statusMessage    = p.message;
      _downloadProgress = p.progress;
      _status = p.progress >= 1.0 ? EnvironmentStatus.ready : EnvironmentStatus.downloading;
      notifyListeners();
    });
    await _checkExistingEnvironment();
  }

  Future<void> _checkExistingEnvironment() async {
    _setLoading(true);
    try {
      // First, try to get the installed environment from native side
      final installedEnv = await _service.getInstalledEnvironment();
      
      if (installedEnv != null) {
        installedEnv.status = EnvironmentStatus.ready;
        _currentEnvironment = installedEnv;
        _status = EnvironmentStatus.ready;
        _service.setCurrentEnvironment(installedEnv);
        await _loadInstalledPackages();
        await _saveEnvConfig(installedEnv);
        
        // Check for proot update silently in background
        _service.checkProotUpdate();
        
        _setLoading(false);
        notifyListeners();
        if (!_initCompleter.isCompleted) _initCompleter.complete();
        return;
      }

      // Fallback: Check known environments
      final knownEnvs = [
        LinuxEnvironment.defaultAlpine(),
        LinuxEnvironment.defaultUbuntu(),
      ];
      
      for (final env in knownEnvs) {
        final installed = await _service.checkEnvironmentInstalled(env.id);
        if (installed) {
          env.status = EnvironmentStatus.ready;
          _currentEnvironment = env;
          _status = EnvironmentStatus.ready;
          _service.setCurrentEnvironment(env);
          await _loadInstalledPackages();
          await _saveEnvConfig(env);
          
          _service.checkProotUpdate();
          break;
        }
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
      notifyListeners();
      if (!_initCompleter.isCompleted) _initCompleter.complete();
    }
  }

  Future<void> _saveEnvConfig(LinuxEnvironment env) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEnvId, env.id);
      await prefs.setString(_kLastDistro, env.distribution);
      await prefs.setBool(_kEnvInstalled, true);
    } catch (_) {}
  }

  Future<void> installEnvironment(LinuxEnvironment environment) async {
    _setLoading(true);
    _status = EnvironmentStatus.downloading;
    _errorMessage = null;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final installed = await _service.installEnvironment(environment);
      _currentEnvironment = installed;
      _status = installed.status;
      _service.setCurrentEnvironment(installed);
      if (installed.isReady) {
        await _loadInstalledPackages();
        await _saveEnvConfig(installed);
      }
    } catch (e) {
      _status = EnvironmentStatus.error;
      _errorMessage = e.toString();
    } finally {
      _downloadProgress = 0.0;
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> _loadInstalledPackages() async {
    try {
      _installedPackages = await _service.listInstalledPackages();
      notifyListeners();
    } catch (_) {}
  }

  Future<ExecutionResult> installPackage(String packageName, {String? version}) async {
    if (!isReady) return ExecutionResult(output: '', error: 'Environment not ready', exitCode: -1, executionTime: Duration.zero);
    _setLoading(true);
    notifyListeners();
    try {
      final result = await _service.installPackage(packageName, version: version);
      if (result.isSuccess) {
        await _loadInstalledPackages();
      } else {
        _errorMessage = result.error;
      }
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      return ExecutionResult(output: '', error: e.toString(), exitCode: -1, executionTime: Duration.zero);
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<ExecutionResult> uninstallPackage(String packageName) async {
    if (!isReady) return ExecutionResult(output: '', error: 'Environment not ready', exitCode: -1, executionTime: Duration.zero);
    _setLoading(true);
    notifyListeners();
    try {
      final result = await _service.uninstallPackage(packageName);
      if (result.isSuccess) await _loadInstalledPackages();
      return result;
    } finally {
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<ExecutionResult> executeCommand(String command) async {
    if (!isReady || _currentEnvironment == null) {
      return ExecutionResult(output: '', error: 'Environment not ready', exitCode: -1, executionTime: Duration.zero);
    }
    return _service.executeInEnvironment(_currentEnvironment!, command);
  }

  Future<ExecutionResult> executePythonCode(String code) async {
    return _service.executePythonCode(code);
  }

  Future<ExecutionResult> runLlamaModel(String modelPath, {
    String prompt      = '',
    int    maxTokens   = 256,
    double temperature = 0.7,
    String backend     = 'llama_cpp_python',
  }) async {
    return _service.runLlamaModel(modelPath,
        prompt: prompt, maxTokens: maxTokens,
        temperature: temperature, backend: backend);
  }

  Future<ExecutionResult> runCommand(String command, {int timeoutMs = 120000}) async {
    return _service.runCommand(command, timeoutMs: timeoutMs);
  }

  Future<String?> saveFileToDownloads(String sourcePath, String fileName) async {
    return _service.saveFileToDownloads(sourcePath, fileName);
  }

  Future<void> shareFile(String filePath) async {
    return _service.shareFile(filePath);
  }

  Future<Map<String, dynamic>> getStorageInfo() async {
    return _service.getStorageInfo();
  }

  Future<void> resetEnvironment() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastEnvId);
      await prefs.remove(_kLastDistro);
      await prefs.remove(_kEnvInstalled);
    } catch (_) {}
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    _progressSubscription?.cancel();
    if (!_initCompleter.isCompleted) _initCompleter.complete();
    super.dispose();
  }
}
