import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/linux_environment.dart';
import '../providers/linux_environment_provider.dart';
import 'main_screen.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0;
  LinuxEnvironment? _selectedEnv;

  final _envOptions = [
    LinuxEnvironment.defaultAlpine(),
    LinuxEnvironment.defaultUbuntu(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Setup Python IDE', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (_step + 1) / 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 20),
              Expanded(child: _buildStep()),
              _buildButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _welcomeStep();
      case 1: return _envSelectStep();
      case 2: return _installStep();
      default: return const SizedBox.shrink();
    }
  }

  Widget _welcomeStep() {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.terminal, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Full Python on Android', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(
            'This app downloads a real Linux environment (Alpine or Ubuntu) and runs it on your device using proot — no root needed.\n\n'
            'You can install ANY Python package, including:',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _feature(Icons.memory, 'TensorFlow / PyTorch', 'Full ARM64 support'),
          _feature(Icons.hub, 'Transformers / HuggingFace', 'Local AI models'),
          _feature(Icons.science, 'NumPy, Pandas, Matplotlib', 'Data science stack'),
          _feature(Icons.terminal, 'Full bash shell', 'Run any Linux command'),
          _feature(Icons.psychology, 'Local LLMs via llama.cpp', 'Import .gguf models'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: theme.colorScheme.onPrimaryContainer, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'First setup requires ~200MB download and ~10 minutes. Subsequent starts are instant.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: 0.05);
  }

  Widget _feature(IconData icon, String title, String sub) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(sub,   style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          )),
        ],
      ),
    );
  }

  Widget _envSelectStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose Linux Distribution', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Alpine is faster to setup. Ubuntu is more compatible with Python packages that need glibc.',
             style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        ...(_envOptions.map((env) {
          final sel = _selectedEnv?.id == env.id;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: sel ? theme.colorScheme.primaryContainer : null,
            child: ListTile(
              leading: Radio<String>(
                value: env.id,
                groupValue: _selectedEnv?.id,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _selectedEnv = env),
              ),
              onTap: () => setState(() => _selectedEnv = env),
              title: Text(env.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Python ${env.metadata['python_version']} • ~${env.metadata['size_mb']} MB download'),
                  if (env.distribution == 'alpine')
                    const Text('✅ Faster • Good for most packages')
                  else
                    const Text('✅ Better glibc compatibility • TF/Torch easier'),
                ],
              ),
            ),
          );
        })),
      ],
    ).animate().fadeIn().slideX(begin: 0.05);
  }

  Widget _installStep() {
    return Consumer<LinuxEnvironmentProvider>(
      builder: (ctx, provider, _) {
        final theme = Theme.of(ctx);
        final navigator = Navigator.of(ctx);

        if (provider.status == EnvironmentStatus.ready) {
          Future.microtask(() {
            if (mounted) {
              navigator.pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
            }
          });
        }

        final isError = provider.status == EnvironmentStatus.error;
        final isDone  = provider.status == EnvironmentStatus.ready;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100, height: 100,
              child: isDone
                ? const Icon(Icons.check_circle, size: 80, color: Colors.green)
                : isError
                  ? Icon(Icons.error, size: 80, color: theme.colorScheme.error)
                  : CircularProgressIndicator(
                      value: provider.downloadProgress > 0 ? provider.downloadProgress : null,
                      strokeWidth: 8,
                    ),
            ),
            const SizedBox(height: 24),

            // Live status message from native
            Text(
              provider.statusMessage.isNotEmpty ? provider.statusMessage : provider.statusDisplay,
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDone ? Colors.green : isError ? theme.colorScheme.error : null,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            if (provider.downloadProgress > 0 && !isDone && !isError) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: provider.downloadProgress),
              const SizedBox(height: 6),
              Text('${(provider.downloadProgress * 100).toStringAsFixed(1)}%',
                   style: theme.textTheme.bodySmall),
            ],

            const SizedBox(height: 16),

            if (isError) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      provider.errorMessage ?? 'Installation failed',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Check your internet connection\n'
                      '• Ensure 500MB+ free storage\n'
                      '• Try the other distro (Alpine/Ubuntu)\n'
                      '• Wait a moment and tap Retry',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  provider.clearError();
                  if (_selectedEnv != null) provider.installEnvironment(_selectedEnv!);
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],

            if (!isDone && !isError) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Row(children: [
                      Icon(Icons.timer, size: 16),
                      SizedBox(width: 6),
                      Text('This takes ~10-20 minutes on first setup'),
                    ]),
                    SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.wifi, size: 16),
                      SizedBox(width: 6),
                      Text('Keep the app open and WiFi connected'),
                    ]),
                  ],
                ),
              ),
            ],
          ],
        ).animate().fadeIn();
      },
    );
  }

  Widget _buildButtons() {
    final canNext = _step == 0 || (_step == 1 && _selectedEnv != null);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_step > 0 && _step < 2)
          TextButton.icon(
            onPressed: () => setState(() => _step--),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          )
        else
          const SizedBox.shrink(),
        if (_step < 2)
          FilledButton.icon(
            onPressed: canNext ? () {
              setState(() => _step++);
              if (_step == 2 && _selectedEnv != null) {
                context.read<LinuxEnvironmentProvider>().installEnvironment(_selectedEnv!);
              }
            } : null,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next'),
          ),
      ],
    );
  }
}
