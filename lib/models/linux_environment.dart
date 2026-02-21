enum EnvironmentStatus {
  notInstalled,
  downloading,
  installing,
  ready,
  error,
  updating,
}

enum Architecture {
  arm64,
  armv7,
  x86_64,
  unknown;

  static Architecture fromString(String arch) {
    switch (arch.toLowerCase()) {
      case 'arm64':
      case 'aarch64':
        return Architecture.arm64;
      case 'armv7':
      case 'armv7l':
      case 'arm':
        return Architecture.armv7;
      case 'x86_64':
      case 'amd64':
        return Architecture.x86_64;
      default:
        return Architecture.unknown;
    }
  }

  String get displayName {
    switch (this) {
      case Architecture.arm64:
        return 'ARM64';
      case Architecture.armv7:
        return 'ARMv7';
      case Architecture.x86_64:
        return 'x86_64';
      case Architecture.unknown:
        return 'Unknown';
    }
  }
}

class LinuxEnvironment {
  final String id;
  final String name;
  final String distribution;
  final String version;
  final Architecture architecture;
  EnvironmentStatus status;
  double downloadProgress;
  String? errorMessage;
  DateTime? installedAt;
  Map<String, dynamic> metadata;

  LinuxEnvironment({
    required this.id,
    required this.name,
    required this.distribution,
    required this.version,
    required this.architecture,
    this.status = EnvironmentStatus.notInstalled,
    this.downloadProgress = 0.0,
    this.errorMessage,
    this.installedAt,
    this.metadata = const {},
  });

  factory LinuxEnvironment.defaultAlpine() {
    return LinuxEnvironment(
      id: 'alpine-3.19',
      name: 'Alpine Linux',
      distribution: 'alpine',
      version: '3.19',
      architecture: Architecture.arm64,
      metadata: {
        'python_version': '3.11',
        'size_mb': 150,
        'packages': ['python3', 'pip', 'gcc', 'musl-dev', 'linux-headers'],
      },
    );
  }

  factory LinuxEnvironment.defaultUbuntu() {
    return LinuxEnvironment(
      id: 'ubuntu-22.04',
      name: 'Ubuntu',
      distribution: 'ubuntu',
      version: '22.04',
      architecture: Architecture.arm64,
      metadata: {
        'python_version': '3.10',
        'size_mb': 500,
        'packages': ['python3', 'python3-pip', 'build-essential'],
      },
    );
  }

  bool get isReady => status == EnvironmentStatus.ready;
  bool get isInstalling => 
    status == EnvironmentStatus.downloading || 
    status == EnvironmentStatus.installing;

  String get statusDisplay {
    switch (status) {
      case EnvironmentStatus.notInstalled:
        return 'Not Installed';
      case EnvironmentStatus.downloading:
        return 'Downloading (${(downloadProgress * 100).toStringAsFixed(1)}%)';
      case EnvironmentStatus.installing:
        return 'Installing...';
      case EnvironmentStatus.ready:
        return 'Ready';
      case EnvironmentStatus.error:
        return 'Error: $errorMessage';
      case EnvironmentStatus.updating:
        return 'Updating...';
    }
  }
}

class PythonInstallation {
  final String version;
  final String path;
  final List<String> installedPackages;
  final DateTime? lastUpdated;

  PythonInstallation({
    required this.version,
    required this.path,
    this.installedPackages = const [],
    this.lastUpdated,
  });

  factory PythonInstallation.fromVersionOutput(String output) {
    // Parse "Python 3.11.4" format
    final versionMatch = RegExp(r'Python (\d+\.\d+\.\d+)').firstMatch(output);
    final version = versionMatch?.group(1) ?? 'unknown';
    
    return PythonInstallation(
      version: version,
      path: '/usr/bin/python3',
      installedPackages: [],
    );
  }
}

class ProcessInfo {
  final int pid;
  final String command;
  final DateTime startTime;
  ProcessStatus status;

  ProcessInfo({
    required this.pid,
    required this.command,
    required this.startTime,
    this.status = ProcessStatus.running,
  });
}

enum ProcessStatus {
  running,
  paused,
  terminated,
  error,
}

class EnvironmentStats {
  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final int processCount;
  final DateTime timestamp;

  EnvironmentStats({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskUsage,
    required this.processCount,
    required this.timestamp,
  });

  factory EnvironmentStats.empty() {
    return EnvironmentStats(
      cpuUsage: 0.0,
      memoryUsage: 0.0,
      diskUsage: 0.0,
      processCount: 0,
      timestamp: DateTime.now(),
    );
  }
}
