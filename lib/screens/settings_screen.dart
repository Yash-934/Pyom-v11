import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../providers/editor_provider.dart';
import '../providers/linux_environment_provider.dart';
import 'setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final editorProvider = context.watch<EditorProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Appearance section
          _buildSectionHeader(context, 'Appearance'),
          
          ListTile(
            leading: const Icon(Icons.brightness_medium),
            title: const Text('Theme'),
            subtitle: Text(_getThemeModeName(themeProvider.themeMode)),
            trailing: DropdownButton<ThemeMode>(
              value: themeProvider.themeMode,
              underline: const SizedBox.shrink(),
              onChanged: (mode) {
                if (mode != null) {
                  themeProvider.setThemeMode(mode);
                }
              },
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('System'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('Light'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('Dark'),
                ),
              ],
            ),
          ),
          
          const Divider(),
          
          // Editor section
          _buildSectionHeader(context, 'Editor'),
          
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('Font Size'),
            subtitle: Text('${editorProvider.fontSize.toInt()}pt'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => editorProvider.setFontSize(
                    editorProvider.fontSize - 1,
                  ),
                  icon: const Icon(Icons.remove),
                ),
                Text('${editorProvider.fontSize.toInt()}'),
                IconButton(
                  onPressed: () => editorProvider.setFontSize(
                    editorProvider.fontSize + 1,
                  ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          
          SwitchListTile(
            secondary: const Icon(Icons.format_list_numbered),
            title: const Text('Show Line Numbers'),
            value: editorProvider.showLineNumbers,
            onChanged: (_) => editorProvider.toggleLineNumbers(),
          ),
          
          SwitchListTile(
            secondary: const Icon(Icons.wrap_text),
            title: const Text('Word Wrap'),
            value: editorProvider.wordWrap,
            onChanged: (_) => editorProvider.toggleWordWrap(),
          ),
          
          const Divider(),
          
          // Environment section
          _buildSectionHeader(context, 'Linux Environment'),

          Consumer<LinuxEnvironmentProvider>(
            builder: (ctx, linuxProvider, _) {
              final isReady = linuxProvider.isReady;
              final env = linuxProvider.currentEnvironment;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(
                      isReady ? Icons.check_circle : Icons.error_outline,
                      color: isReady ? Colors.green : Theme.of(ctx).colorScheme.error,
                    ),
                    title: Text(isReady ? 'Environment Ready' : 'Not Configured'),
                    subtitle: Text(
                      isReady
                        ? '${env?.name ?? "Linux"} • Python ${env?.metadata["python_version"] ?? "3.x"}'
                        : 'Tap "Install" to set up Python on this device',
                    ),
                  ),
                  if (!isReady)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const SetupScreen()));
                          },
                          icon: const Icon(Icons.download),
                          label: const Text('Install Linux Environment'),
                        ),
                      ),
                    ),
                  if (isReady) ...[
                    ListTile(
                      leading: const Icon(Icons.memory),
                      title: const Text('Storage Info'),
                      subtitle: FutureBuilder<Map<String, dynamic>>(
                        future: linuxProvider.getStorageInfo(),
                        builder: (ctx, snap) {
                          if (!snap.hasData) return const Text('Loading…');
                          final data = snap.data!;
                          return Text(
                            'Free: ${data["freeSpaceMB"] ?? 0} MB / '
                            'Total: ${data["totalSpaceMB"] ?? 0} MB',
                          );
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.refresh, color: Colors.orange),
                      title: const Text('Reinstall Environment'),
                      subtitle: const Text('Remove and reinstall (all packages will be lost)'),
                      onTap: () => _showResetConfirmation(ctx),
                    ),
                  ],
                ],
              );
            },
          ),

          const Divider(),

          // About section
          _buildSectionHeader(context, 'About'),

          const ListTile(
            leading: Icon(Icons.info),
            title: Text('Version'),
            subtitle: Text('1.1.0 — Pyom Python IDE'),
          ),

          ListTile(
            leading: const Icon(Icons.description),
            title: const Text('License'),
            subtitle: const Text('MIT License'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getThemeModeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Follow system';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  void _showResetConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Environment'),
        content: const Text(
          'This will delete the Linux environment and all installed packages. '
          'Your project files will be preserved. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // Reset environment
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

// This method adds Linux environment section — call from within build() body
// The actual settings_screen already has basic sections. 
// We add a patch via a separate widget used in settings.
