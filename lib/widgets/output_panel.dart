import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';

class OutputPanel extends StatelessWidget {
  final VoidCallback onClose;

  const OutputPanel({
    super.key,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editorProvider = context.watch<EditorProvider>();
    
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Header
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(128),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.output,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'OUTPUT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (editorProvider.isExecuting)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () {
                    editorProvider.clearOutput();
                  },
                  icon: const Icon(Icons.clear_all, size: 16),
                  tooltip: 'Clear',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Close',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
          
          // Output content
          Expanded(
            child: Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.all(12),
              child: _buildOutputContent(context, editorProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputContent(BuildContext context, EditorProvider editorProvider) {
    final theme = Theme.of(context);
    
    if (editorProvider.executionOutput.isEmpty && 
        editorProvider.executionError.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
            ),
            const SizedBox(height: 8),
            Text(
              'Run your code to see output here',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(178),
              ),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (editorProvider.executionOutput.isNotEmpty)
            SelectableText(
              editorProvider.executionOutput,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          if (editorProvider.executionError.isNotEmpty)
            SelectableText(
              editorProvider.executionError,
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 12,
                color: theme.colorScheme.error,
                height: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
