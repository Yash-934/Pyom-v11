import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../providers/linux_environment_provider.dart';
import '../models/python_package.dart';

class PackageManagerScreen extends StatefulWidget {
  const PackageManagerScreen({super.key});

  @override
  State<PackageManagerScreen> createState() => _PackageManagerScreenState();
}

class _PackageManagerScreenState extends State<PackageManagerScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linuxProvider = context.watch<LinuxEnvironmentProvider>();
    
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Header
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  Icons.extension,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Packages',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (linuxProvider.isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search packages...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _isSearching = false;
                          });
                        },
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onSubmitted: (value) {
                setState(() {
                  _isSearching = value.isNotEmpty;
                });
              },
            ),
          ),
          
          // Quick install chips
          if (!_isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildQuickInstallChip('numpy', 'NumPy'),
                  _buildQuickInstallChip('pandas', 'Pandas'),
                  _buildQuickInstallChip('matplotlib', 'Matplotlib'),
                  _buildQuickInstallChip('requests', 'Requests'),
                  _buildQuickInstallChip('flask', 'Flask'),
                  _buildQuickInstallChip('django', 'Django'),
                  _buildQuickInstallChip('torch', 'PyTorch'),
                  _buildQuickInstallChip('tensorflow', 'TensorFlow'),
                  _buildQuickInstallChip('transformers', 'Transformers'),
                  _buildQuickInstallChip('llama-cpp-python', 'Llama.cpp'),
                ],
              ),
            ),
          
          const Divider(height: 24),
          
          // Package list
          Expanded(
            child: _isSearching
                ? _buildSearchResults()
                : _buildInstalledPackages(linuxProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickInstallChip(String packageName, String label) {
    final linuxProvider = context.read<LinuxEnvironmentProvider>();
    final isInstalled = linuxProvider.installedPackages
        .any((p) => p.name.toLowerCase() == packageName.toLowerCase());
    
    return ActionChip(
      avatar: isInstalled 
          ? const Icon(Icons.check, size: 16) 
          : const Icon(Icons.add, size: 16),
      label: Text(label),
      onPressed: isInstalled 
          ? null 
          : () => _installPackage(packageName),
    );
  }

  Widget _buildInstalledPackages(LinuxEnvironmentProvider provider) {
    final theme = Theme.of(context);
    
    if (provider.installedPackages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.extension_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
            ),
            const SizedBox(height: 16),
            Text(
              'No packages installed',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search or select a package to install',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(178),
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: provider.installedPackages.length,
      itemBuilder: (context, index) {
        final package = provider.installedPackages[index];
        return _PackageListItem(
          package: package,
          onUninstall: () => _uninstallPackage(package.name),
        ).animate(delay: (index * 30).ms).fadeIn().slideX(begin: 0.1);
      },
    );
  }

  Widget _buildSearchResults() {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(128),
          ),
          const SizedBox(height: 16),
          Text(
            'Search PyPI',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Press Enter to search for "${_searchController.text}"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(178),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _installPackage(_searchController.text),
            icon: const Icon(Icons.download),
            label: Text('Install ${_searchController.text}'),
          ),
        ],
      ),
    );
  }

  Future<void> _installPackage(String packageName) async {
    final linuxProvider = context.read<LinuxEnvironmentProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Installing $packageName'),
        content: const Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Please wait...'),
          ],
        ),
      ),
    );
    
    await linuxProvider.installPackage(packageName);
    
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('$packageName installed successfully'),
      ),
    );
  }

  Future<void> _uninstallPackage(String packageName) async {
    if (!mounted) return;
    final linuxProvider = context.read<LinuxEnvironmentProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final currentTheme = Theme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Uninstall $packageName?'),
        content: Text('Are you sure you want to uninstall $packageName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: currentTheme.colorScheme.error,
            ),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await linuxProvider.uninstallPackage(packageName);
      
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('$packageName uninstalled'),
        ),
      );
    }
  }
}

class _PackageListItem extends StatelessWidget {
  final PythonPackage package;
  final VoidCallback onUninstall;

  const _PackageListItem({
    required this.package,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.extension,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          package.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'Version: ${package.version}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: IconButton(
          onPressed: onUninstall,
          icon: Icon(
            Icons.delete_outline,
            color: theme.colorScheme.error,
          ),
          tooltip: 'Uninstall',
        ),
      ),
    );
  }
}
