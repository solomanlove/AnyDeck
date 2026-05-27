/// adb 和 adb shell 命令的统一执行结果。
class AdbResult {
  const AdbResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// adb 约定 exitCode 为 0 表示命令执行成功。
  bool get isSuccess => exitCode == 0;

  /// 面向 SnackBar 或弹窗展示的最佳可读消息。
  String get message {
    if (stdout.trim().isNotEmpty) {
      return stdout.trim();
    }
    if (stderr.trim().isNotEmpty) {
      return stderr.trim();
    }
    return isSuccess ? '命令执行完成' : '命令执行失败';
  }
}
