import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditorProvider extends ChangeNotifier {
  // Editor settings
  double _fontSize = 14.0;
  bool _showLineNumbers = true;
  bool _wordWrap = true;
  bool _showMinimap = false;
  String _theme = 'vs-dark';
  
  // Execution state
  bool _isExecuting = false;
  String _executionOutput = '';
  String _executionError = '';
  int? _currentLine;
  Duration _lastExecutionTime = Duration.zero;
  
  // Search state
  bool _isSearching = false;
  String _searchQuery = '';
  bool _caseSensitive = false;
  bool _wholeWord = false;
  
  // Undo/Redo stacks
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  static const int _maxStackSize = 50;

  // SharedPreferences Keys
  static const _kFontSize = 'editor_font_size';
  static const _kLineNumbers = 'editor_line_numbers';
  static const _kWordWrap = 'editor_word_wrap';
  static const _kTheme = 'editor_theme';

  EditorProvider() {
    _loadSettings();
  }

  // Getters
  double get fontSize => _fontSize;
  bool get showLineNumbers => _showLineNumbers;
  bool get wordWrap => _wordWrap;
  bool get showMinimap => _showMinimap;
  String get theme => _theme;
  bool get isExecuting => _isExecuting;
  String get executionOutput => _executionOutput;
  String get executionError => _executionError;
  int? get currentLine => _currentLine;
  Duration get lastExecutionTime => _lastExecutionTime;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  bool get caseSensitive => _caseSensitive;
  bool get wholeWord => _wholeWord;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _fontSize = prefs.getDouble(_kFontSize) ?? 14.0;
      _showLineNumbers = prefs.getBool(_kLineNumbers) ?? true;
      _wordWrap = prefs.getBool(_kWordWrap) ?? false;
      _theme = prefs.getString(_kTheme) ?? 'vs-dark';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kFontSize, _fontSize);
      await prefs.setBool(_kLineNumbers, _showLineNumbers);
      await prefs.setBool(_kWordWrap, _wordWrap);
      await prefs.setString(_kTheme, _theme);
    } catch (_) {}
  }

  // Settings
  void setFontSize(double size) {
    _fontSize = size.clamp(8.0, 36.0);
    _saveSettings();
    notifyListeners();
  }

  void toggleLineNumbers() {
    _showLineNumbers = !_showLineNumbers;
    _saveSettings();
    notifyListeners();
  }

  void toggleWordWrap() {
    _wordWrap = !_wordWrap;
    _saveSettings();
    notifyListeners();
  }

  void toggleMinimap() {
    _showMinimap = !_showMinimap;
    _saveSettings(); // Assuming this should also be saved
    notifyListeners();
  }

  void setTheme(String theme) {
    _theme = theme;
    _saveSettings();
    notifyListeners();
  }

  // Execution
  void startExecution() {
    _isExecuting = true;
    _executionOutput = '';
    _executionError = '';
    _lastExecutionTime = Duration.zero;
    notifyListeners();
  }

  void setExecutionResult({
    required String output,
    required String error,
    required Duration executionTime,
  }) {
    _isExecuting = false;
    _executionOutput = output;
    _executionError = error;
    _lastExecutionTime = executionTime;
    notifyListeners();
  }

  void clearOutput() {
    _executionOutput = '';
    _executionError = '';
    _lastExecutionTime = Duration.zero;
    notifyListeners();
  }

  void setCurrentLine(int? line) {
    _currentLine = line;
    notifyListeners();
  }

  // Search
  void startSearch() {
    _isSearching = true;
    notifyListeners();
  }

  void stopSearch() {
    _isSearching = false;
    _searchQuery = '';
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void toggleCaseSensitive() {
    _caseSensitive = !_caseSensitive;
    notifyListeners();
  }

  void toggleWholeWord() {
    _wholeWord = !_wholeWord;
    notifyListeners();
  }

  // Undo/Redo
  void pushState(String content) {
    if (_undoStack.isNotEmpty && _undoStack.last == content) {
      return;
    }
    
    _undoStack.add(content);
    if (_undoStack.length > _maxStackSize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    notifyListeners();
  }

  String? undo(String currentContent) {
    if (_undoStack.isEmpty) return null;
    
    _redoStack.add(currentContent);
    final previousState = _undoStack.removeLast();
    notifyListeners();
    return previousState;
  }

  String? redo(String currentContent) {
    if (_redoStack.isEmpty) return null;
    
    _undoStack.add(currentContent);
    final nextState = _redoStack.removeLast();
    notifyListeners();
    return nextState;
  }

  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    notifyListeners();
  }
}
