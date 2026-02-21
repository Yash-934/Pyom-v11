class PythonPackage {
  final String name;
  final String version;
  final bool isInstalled;

  PythonPackage({
    required this.name,
    required this.version,
    this.isInstalled = false,
  });
}
