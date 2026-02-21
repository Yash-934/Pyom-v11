import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/terminal_provider.dart';

// ── Catppuccin Mocha palette (same as editor) ─────────────────────────────
class _Mocha {
  static const bg      = Color(0xFF1E1E2E);
  static const surface = Color(0xFF181825);
  static const overlay = Color(0xFF313244);
  static const muted   = Color(0xFF45475A);
  static const text    = Color(0xFFCDD6F4);
  static const subtext = Color(0xFFBAC2DE);
  static const green   = Color(0xFFA6E3A1);
  static const red     = Color(0xFFF38BA8);
  static const yellow  = Color(0xFFF9E2AF);
  static const blue    = Color(0xFF89B4FA);
  static const mauve   = Color(0xFFCBA6F7);
}

class TerminalPanel extends StatefulWidget {
  final VoidCallback onClose;
  const TerminalPanel({super.key, required this.onClose});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final _inputCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _focusNode   = FocusNode();
  final _historyNode = FocusNode();

  int _historyIndex = -1;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _historyNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submitCommand(TerminalProvider tp) {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _historyIndex = -1;
    tp.executeCommand(text);
    _inputCtrl.clear();
    if (mounted) { // Guard with mounted check
      _scrollToBottom();
    }
  }

  void _navigateHistory(TerminalProvider tp, bool up) {
    final history = tp.commandHistory;
    if (history.isEmpty) return;
    if (!mounted) return; // Guard with mounted check
    setState(() {
      if (up) {
        _historyIndex = (_historyIndex + 1).clamp(0, history.length - 1);
      } else {
        _historyIndex--;
        if (_historyIndex < 0) { _historyIndex = -1; _inputCtrl.clear(); return; }
      }
      _inputCtrl.text = history[_historyIndex];
      _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TerminalProvider>();
    _scrollToBottom();

    return Container(
      decoration: const BoxDecoration(color: _Mocha.bg),
      child: Column(
        children: [
          _buildHeader(tp),
          Expanded(child: _buildOutput(tp)),
          _buildInput(tp),
        ],
      ),
    );
  }

  // ── Header bar ────────────────────────────────────────────────────────────

  Widget _buildHeader(TerminalProvider tp) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: _Mocha.surface,
        border: Border(bottom: BorderSide(color: _Mocha.overlay)),
      ),
      child: Row(
        children: [
          // Traffic-light style dots
          _dot(_Mocha.red),
          const SizedBox(width: 6),
          _dot(_Mocha.yellow),
          const SizedBox(width: 6),
          _dot(_Mocha.green),
          const SizedBox(width: 12),
          const Icon(Icons.terminal, size: 14, color: _Mocha.mauve),
          const SizedBox(width: 6),
          const Text(
            'TERMINAL',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _Mocha.subtext,
              letterSpacing: 1.2,
            ),
          ),
          if (tp.isExecuting) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5, color: _Mocha.green,
              ),
            ),
          ],
          const Spacer(),
          // Copy last output
          _headerBtn(Icons.copy_outlined, 'Copy output', () {
            if (tp.lines.isNotEmpty) {
              Clipboard.setData(ClipboardData(
                text: tp.lines.map((l) => l.text).join('\n'),
              ));
            }
          }),
          _headerBtn(Icons.clear_all_rounded, 'Clear', tp.clear),
          _headerBtn(Icons.close_rounded, 'Close', widget.onClose),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  Widget _headerBtn(IconData icon, String tooltip, VoidCallback onTap) =>
    Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 14, color: _Mocha.subtext),
        ),
      ),
    );

  // ── Output area ───────────────────────────────────────────────────────────

  Widget _buildOutput(TerminalProvider tp) {
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Container(
        color: _Mocha.bg,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: tp.lines.isEmpty
          ? _emptyState()
          : ListView.builder(
              controller: _scrollCtrl,
              itemCount:  tp.lines.length,
              itemBuilder: (_, i) => _buildLine(tp.lines[i]),
            ),
      ),
    );
  }

  Widget _emptyState() => const Column( // Added const
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.terminal, size: 32, color: _Mocha.overlay),
      SizedBox(height: 8),
      Text(
        'Terminal ready. Type a command below.',
        style: TextStyle(
          fontFamily: 'monospace', fontSize: 12, color: _Mocha.muted,
        ),
      ),
    ],
  );

  Widget _buildLine(TerminalLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: SelectableText(
        line.text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize:   12.5,
          height:     1.55,
          color:      _lineColor(line.type),
          fontWeight: line.type == TerminalLineType.input
              ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Color _lineColor(TerminalLineType type) {
    switch (type) {
      case TerminalLineType.input:  return _Mocha.green;
      case TerminalLineType.error:  return _Mocha.red;
      case TerminalLineType.system: return _Mocha.mauve;
      case TerminalLineType.warn:   return _Mocha.yellow;
      case TerminalLineType.info:   return _Mocha.blue;
      case TerminalLineType.output: return _Mocha.text;
    }
  }

  // ── Input bar ─────────────────────────────────────────────────────────────

  Widget _buildInput(TerminalProvider tp) {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      decoration: const BoxDecoration(
        color: _Mocha.surface,
        border: Border(top: BorderSide(color: _Mocha.overlay)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Prompt
          Text(
            tp.prompt,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: _Mocha.green,
              fontWeight: FontWeight.bold,
            ),
          ),

          // Input field
          Expanded(
            child: KeyboardListener(
              focusNode: _historyNode,
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _navigateHistory(tp, true);
                  } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    _navigateHistory(tp, false);
                  }
                }
              },
              child: TextField(
                controller: _inputCtrl,
                focusNode:  _focusNode,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize:   13,
                  color:      _Mocha.text,
                  height:     1.4,
                ),
                cursorColor: _Mocha.mauve,
                decoration: const InputDecoration(
                  border:          InputBorder.none,
                  isDense:         true,
                  contentPadding:  EdgeInsets.symmetric(horizontal: 6),
                  hintText:        'Type a command…',
                  hintStyle:       TextStyle(
                    fontFamily: 'monospace', fontSize: 12,
                    color: _Mocha.muted,
                  ),
                ),
                onSubmitted: (_) => _submitCommand(tp),
              ),
            ),
          ),

          // Send button
          _sendButton(tp),
        ],
      ),
    );
  }

  Widget _sendButton(TerminalProvider tp) {
    return GestureDetector(
      onTap: tp.isExecuting ? null : () => _submitCommand(tp),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin:  const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tp.isExecuting ? _Mocha.overlay : _Mocha.mauve.withOpacity(0.1),
          border: Border.all(
            color: tp.isExecuting ? _Mocha.muted : _Mocha.mauve,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          tp.isExecuting ? '⏳' : '↵',
          style: TextStyle(
            fontSize: 13,
            color: tp.isExecuting ? _Mocha.muted : _Mocha.mauve,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}