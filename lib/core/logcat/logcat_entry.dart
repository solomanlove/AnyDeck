/// Logcat 日志等级，按 Android logcat 的优先级从低到高排列。
enum LogcatLevel {
  verbose('V', 0),
  debug('D', 1),
  info('I', 2),
  warning('W', 3),
  error('E', 4),
  assertLevel('A', 5),
  unknown('', -1);

  const LogcatLevel(this.label, this.priority);

  final String label;
  final int priority;

  static LogcatLevel fromLabel(String value) {
    return switch (value.trim().toUpperCase()) {
      'V' => LogcatLevel.verbose,
      'D' => LogcatLevel.debug,
      'I' => LogcatLevel.info,
      'W' => LogcatLevel.warning,
      'E' => LogcatLevel.error,
      'A' || 'F' => LogcatLevel.assertLevel,
      _ => LogcatLevel.unknown,
    };
  }
}

/// Logcat 过滤下限。选择 warning 时显示 W/E/A，选择 verbose 时显示全部。
enum LogcatLevelFilter {
  verbose('VERBOSE', LogcatLevel.verbose),
  debug('DEBUG', LogcatLevel.debug),
  info('INFO', LogcatLevel.info),
  warning('WARN', LogcatLevel.warning),
  error('ERROR', LogcatLevel.error);

  const LogcatLevelFilter(this.label, this.minimumLevel);

  final String label;
  final LogcatLevel minimumLevel;
}

/// Logcat 展示模式。
enum LogcatViewMode { standard, compact, plain, raw }

/// 结构化后的单行 Logcat。
class LogcatEntry {
  const LogcatEntry({
    required this.rawLine,
    this.timestamp = '',
    this.pid = '',
    this.tid = '',
    this.level = LogcatLevel.unknown,
    this.tag = '',
    this.packageName = '',
    this.message = '',
  });

  final String rawLine;
  final String timestamp;
  final String pid;
  final String tid;
  final LogcatLevel level;
  final String tag;
  final String packageName;
  final String message;

  String get pidTid {
    if (pid.isEmpty && tid.isEmpty) {
      return '';
    }
    return '$pid-$tid';
  }

  String get searchableText {
    return [
      timestamp,
      pid,
      tid,
      level.label,
      tag,
      packageName,
      message,
      rawLine,
    ].join(' ');
  }

  LogcatEntry copyWithPackage(String packageName) {
    if (packageName.isEmpty || this.packageName == packageName) {
      return this;
    }
    return LogcatEntry(
      rawLine: rawLine,
      timestamp: timestamp,
      pid: pid,
      tid: tid,
      level: level,
      tag: tag,
      packageName: packageName,
      message: message,
    );
  }
}

/// 解析 `adb logcat -v threadtime` 常见格式。
///
/// 示例：
/// `05-28 15:18:06.252 25586 25710 W BpBinder: Slow Binder...`
LogcatEntry parseLogcatLine(
  String line, {
  Map<String, String> pidPackages = const {},
}) {
  final match = _threadtimePattern.firstMatch(line);
  if (match == null) {
    return LogcatEntry(rawLine: line, message: line);
  }

  final pid = match.namedGroup('pid') ?? '';
  final level = LogcatLevel.fromLabel(match.namedGroup('level') ?? '');
  final tag = (match.namedGroup('tag') ?? '').trimRight();
  final message = match.namedGroup('message') ?? '';

  return LogcatEntry(
    rawLine: line,
    timestamp: match.namedGroup('time') ?? '',
    pid: pid,
    tid: match.namedGroup('tid') ?? '',
    level: level,
    tag: tag,
    packageName: pidPackages[pid] ?? '',
    message: message,
  );
}

final RegExp _threadtimePattern = RegExp(
  r'^(?<time>\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d{3})\s+'
  r'(?<pid>\d+)\s+'
  r'(?<tid>\d+)\s+'
  r'(?<level>[VDIWEAF])\s+'
  r'(?<tag>[^:]*):\s?'
  r'(?<message>.*)$',
);
