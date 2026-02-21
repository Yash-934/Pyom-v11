import 'dart:async';
import 'package:flutter/material.dart';

import '../services/linux_environment_service.dart';
import './linux_environment_provider.dart';

class TerminalProvider extends ChangeNotifier {
  final LinuxEnvironmentProvider _linuxProvider;
  final LinuxEnvironmentService _service;

  final List<TerminalLine> _lines = [];
  final _inputController = StreamController<String>.broadcast();
  bool _isReady = false;
  String _currentDirectory = '~';
  String _prompt = '\$ ';
  bool _isExecuting = false;
  final List<String> _commandHistory = []; // Added: Command history list

  StreamSubscription? _outputSubscription;

  TerminalProvider(this._linuxProvider, this._service) {
    _initialize();
  }

  // Getters
  List<TerminalLine> get lines => List.unmodifiable(_lines);
  Stream<String> get inputStream => _inputController.stream;
  bool get isReady => _isReady;
  String get currentDirectory => _currentDirectory;
  String get prompt => _prompt;
  bool get isExecuting => _isExecuting;
  List<String> get commandHistory => List.unmodifiable(_commandHistory); // Added: Command history getter

  Future<void> _initialize() async {
    _outputSubscription = _service.outputStream.listen(
      _onOutput,
      onError: _onError,
    );

    // Add welcome message
    _addLine(
      'Python IDE Terminal',
      type: TerminalLineType.system,
    );
    _addLine(
      'Linux environment loading...',
      type: TerminalLineType.system,
    );

    // Check if environment is ready
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_linuxProvider.isReady) {
        _isReady = true;
        _addLine(
          'Environment ready. Type commands below.',
          type: TerminalLineType.system,
        );
        _updatePrompt();
        timer.cancel();
        notifyListeners();
      }
    });
  }

  void _onOutput(String output) {
    _addLine(output);
  }

  void _onError(dynamic error) {
    _addLine(
      'Error: $error',
      type: TerminalLineType.error,
    );
  }

  void _addLine(String text, {TerminalLineType type = TerminalLineType.output}) {
    _lines.add(TerminalLine(
      text: text,
      type: type,
      timestamp: DateTime.now(),
    ));

    // Limit lines to prevent memory issues
    if (_lines.length > 1000) {
      _lines.removeAt(0);
    }

    notifyListeners();
  }

  void _updatePrompt() {
    _prompt = '$_currentDirectory\$ ';
  }

  Future<void> executeCommand(String command) async {
    if (command.trim().isEmpty) return;

    // Add command to history
    _commandHistory.insert(0, command.trim()); // Added: Add command to history

    // Add command to terminal
    _addLine('$_prompt$command', type: TerminalLineType.input);

    _isExecuting = true;
    notifyListeners();

    try {
      // Handle built-in commands
      if (_handleBuiltInCommand(command)) {
        _isExecuting = false;
        notifyListeners();
        return;
      }

      // Execute in Linux environment
      final result = await _linuxProvider.executeCommand(command);

      if (result.output.isNotEmpty) {
        _addLine(result.output);
      }

      if (result.error.isNotEmpty) {
        _addLine(result.error, type: TerminalLineType.error);
      }

      // Update directory if cd command
      if (command.trim().startsWith('cd ')) {
        await _updateCurrentDirectory();
      }
    } catch (e) {
      _addLine(
        'Execution error: $e',
        type: TerminalLineType.error,
      );
    } finally {
      _isExecuting = false;
      notifyListeners();
    }
  }

  bool _handleBuiltInCommand(String command) {
    final cmd = command.trim();
    final cmdLower = cmd.toLowerCase();

    // Typo detection: "pip 3" instead of "pip3"
    if (RegExp(r'^pip\s+\d').hasMatch(cmdLower)) {
      _addLine(
        '⚠️ Tip: Use "pip3 install <package>" — not "pip 3"',
        type: TerminalLineType.warn,
      );
      return true;
    }

    // Typo: "python 3" instead of "python3"
    if (RegExp(r'^python\s+\d').hasMatch(cmdLower)) {
      _addLine(
        '⚠️ Tip: Use "python3 script.py" — not "python 3"',
        type: TerminalLineType.warn,
      );
      return true;
    }

    switch (cmdLower) {
      case 'clear':
      case 'cls':
        clear();
        return true;
      case 'exit':
        _addLine(
          'Use the UI to close the terminal.',
          type: TerminalLineType.system,
        );
        return true;
      case 'help':
        _addLine(
          '''Available commands:
  clear/cls       - Clear terminal
  exit            - Close terminal (use UI)
  help            - Show this help
  python3         - Run Python interpreter
  pip3 install X  - Install Python package
  pip3 list       - Show installed packages
  ls              - List files
  cd <dir>        - Change directory
  pwd             - Print working directory
  cat <file>      - Display file contents
  nano/vim        - Text editors (if installed)
  
Heavy packages (after env setup):
  pip3 install tensorflow
  pip3 install transformers torch
  pip3 install llama-cpp-python''',
          type: TerminalLineType.system,
        );
        return true;
      default:
        return false;
    }
  }

  Future<void> _updateCurrentDirectory() async {
    try {
      final result = await _linuxProvider.executeCommand('pwd');
      if (result.isSuccess) {
        _currentDirectory = result.output.trim();
        _updatePrompt();
        notifyListeners();
      }
    } catch (_) {}
  }

  void sendInput(String input) {
    _inputController.add(input);
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _inputController.close();
    _outputSubscription?.cancel();
    super.dispose();
  }
}

enum TerminalLineType {
  input,
  output,
  error,
  system,
  warn, // Added: warn
  info, // Added: info
}

class TerminalLine {
  final String text;
  final TerminalLineType type;
  final DateTime timestamp;

  TerminalLine({
    required this.text,
    required this.type,
    required this.timestamp,
  });

  Color getColor(BuildContext context) {
    final theme = Theme.of(context);

    switch (type) {
      case TerminalLineType.input:
        return theme.colorScheme.primary;
      case TerminalLineType.output:
        return theme.colorScheme.onSurface;
      case TerminalLineType.error:
        return theme.colorScheme.error;
      case TerminalLineType.system:
        return theme.colorScheme.tertiary;
      case TerminalLineType.warn: // Added: warn case
        return theme.colorScheme.tertiary;
      case TerminalLineType.info: // Added: info case
        return theme.colorScheme.tertiary;
    }
  }
}