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

  static final RegExp _deviceNotFoundPattern = RegExp(
    r"adb:\s*device\s+'([^']+)'\s+not\s+found",
    caseSensitive: false,
  );

  /// adb 约定 exitCode 为 0 表示命令执行成功。
  bool get isSuccess => exitCode == 0;

  String get _rawMessage => '${stdout.trim()}\n${stderr.trim()}';

  /// adb 返回的已断开设备 ID。
  String? get disconnectedDeviceId {
    return _deviceNotFoundPattern.firstMatch(_rawMessage)?.group(1);
  }

  /// 当前选中的 adb transport 已经不存在，通常表示无线 adb 或 USB 连接已断开。
  bool get isDeviceDisconnected {
    return disconnectedDeviceId != null;
  }

  /// 面向 SnackBar 或弹窗展示的最佳可读消息。
  String get message {
    if (isDeviceDisconnected) {
      return 'adb已断开';
    }
    if (stdout.trim().isNotEmpty) {
      return stdout.trim();
    }
    if (stderr.trim().isNotEmpty) {
      return stderr.trim();
    }
    return isSuccess ? '命令执行完成' : '命令执行失败';
  }
}
