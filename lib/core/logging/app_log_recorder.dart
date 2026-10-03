import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'local_log_store.dart';

/// 不依赖 Provider 的启动期日志入口；各窗口独立落盘，控制台订阅格式化记录。
class AppLogRecorder {
  static final instance = AppLogRecorder();
  static const maxRecords = 1000;
  static const maxMessageLength = 8000;

  final List<String> _history = [];
  final _events = StreamController<String>.broadcast();
  LocalLogStore? store;
  String source = 'main';
  String windowId = '';
  String? storageError;

  List<String> get history => List.unmodifiable(_history);
  Stream<String> get events => _events.stream;

  /// Provider 初始化前即安装采集，路径不可用时仍保留内存中的错误现场。
  Future<void> initialize(String windowId) async {
    this.windowId = windowId;
    final safeId = windowId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    source = safeId.isEmpty ? 'main' : 'window_$safeId';
    try {
      final root = await getApplicationSupportDirectory();
      store = LocalLogStore(Directory('${root.path}/logs'), '${pid}_$source');
      for (final line in _history) {
        store!.add(line);
      }
      if (windowId.isEmpty) await store!.prune();
    } catch (error) {
      storageError = error.toString();
    }
    record(
      'Session started; ${Platform.operatingSystem}; pid=$pid',
      tag: 'app',
    );
  }

  /// 入内存、落盘和跨窗口转发前统一脱敏、截断。
  void record(String message, {String tag = 'app', String level = 'I'}) {
    final safe = sanitize(message);
    final now = DateTime.now().toIso8601String();
    final line = '$now $level [$source] $tag: $safe';
    _history.add(line);
    if (_history.length > maxRecords) _history.removeAt(0);
    _events.add(line);
    store?.add(line);
    if (level == 'E' || level == 'F') unawaited(store?.flush());
  }

  /// 常见凭据脱敏；自由文本中的业务数据仍需在分享前由用户检查。
  static String sanitize(String message) {
    var safe = message.replaceAllMapped(
      RegExp(
        r'''(["']?authorization["']?\s*[:=]\s*["']?(?:bearer\s+|basic\s+)?)[^\s,;"'}]+''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[REDACTED]',
    );
    safe = safe.replaceAllMapped(
      RegExp(
        r'(\b(?:cookie|set-cookie)\s*[:=]\s*)[^\r\n]+',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[REDACTED]',
    );
    safe = safe.replaceAllMapped(
      RegExp(
        r'''((?:["']?(?:access_token|refresh_token|token|api[_-]?key|password|passwd|secret|cookie|set-cookie)["']?)\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;}]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}[REDACTED]',
    );
    return safe.length > maxMessageLength
        ? '${safe.substring(0, maxMessageLength)}\n[truncated]'
        : safe;
  }

  /// debugPrint 没有等级，按常见故障关键词补充级别，便于筛选已捕获的业务失败。
  static String runtimeLevel(String message) {
    if (RegExp(
      r'\b(error|exception|failed|fatal|panic|timeout|timed out)\b|失败|异常|超时',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'E';
    }
    if (RegExp(
      r'\b(warn|warning)\b|警告',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'W';
    }
    return 'I';
  }

  /// 统一识别严重级别，避免心跳过滤误隐藏失败的轮询命令。
  static bool isKeyLog(String line) =>
      RegExp(r'^\S+\s+[WEF]\s+').hasMatch(line);
}
