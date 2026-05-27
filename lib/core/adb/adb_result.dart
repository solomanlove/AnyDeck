class AdbResult {
  const AdbResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get isSuccess => exitCode == 0;

  String get message {
    if (stdout.trim().isNotEmpty) {
      return stdout.trim();
    }
    if (stderr.trim().isNotEmpty) {
      return stderr.trim();
    }
    return isSuccess ? 'Command completed' : 'Command failed';
  }
}
