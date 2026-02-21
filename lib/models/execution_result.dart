class ExecutionResult {
  final String output;
  final String error;
  final int exitCode;
  final Duration executionTime;

  ExecutionResult({
    required this.output,
    required this.error,
    required this.exitCode,
    required this.executionTime,
  });

  bool get isSuccess => exitCode == 0;
}
