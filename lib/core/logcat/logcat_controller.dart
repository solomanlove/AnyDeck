import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../process/tool_path_resolver.dart';
import 'logcat_entry.dart';
import 'logcat_state.dart';
import 'logcat_line_reader.dart';

/// 管理 adb logcat 进程，并暴露有上限的内存日志缓冲区。
class LogcatController extends Notifier<LogcatState> {
  static const int _maxEntries = 3000;
  static const int _maxHistoryItems = 12;
  static const String _packageHistoryKey = 'logcat.package_filter_history';
  static const String _tagHistoryKey = 'logcat.tag_filter_history';
  static const String _textHistoryKey = 'logcat.text_filter_history';

  Process? _process;
  StreamSubscription<String>? _subscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _pidMapTimer;
  String? _deviceId;
  bool _isHarmony = false;
  Map<String, String> _pidPackages = const {};
  final Queue<LogcatEntry> _pendingEntries = Queue();
  Timer? _batchTimer;
  int _maxLogLength = 0;
  int _sessionRevision = 0;

  int get maxLogLength => _maxLogLength;
  String? get activeDeviceId => _deviceId;

  @override
  LogcatState build() {
    // Riverpod 销毁控制器时，同步停止外部 logcat 进程。
    ref.onDispose(() {
      _sessionRevision++;
      unawaited(_releaseProcess(updateState: false));
    });
    unawaited(_loadFilterHistories());
    return const LogcatState();
  }

  /// 为选中设备启动新的 logcat 进程。鸿蒙设备走 `hdc hilog`，安卓走 `adb logcat`。
  Future<void> start(String deviceId, {bool isHarmony = false}) async {
    final revision = ++_sessionRevision;
    await _releaseProcess(updateState: true);
    if (revision != _sessionRevision || !ref.mounted) return;
    _deviceId = deviceId;
    _isHarmony = isHarmony;
    state = state.copyWith(entries: [], isRunning: true, isPaused: false);
    try {
      await _refreshPidPackages();
      if (revision != _sessionRevision || !ref.mounted) return;
      _pidMapTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshPidPackages(),
      );
      final Process process;
      if (isHarmony) {
        process = await Process.start(resolveToolPath('hdc'), [
          '-t',
          deviceId,
          'hilog',
        ]);
      } else {
        process = await Process.start(resolveToolPath('adb'), [
          '-s',
          deviceId,
          'logcat',
          '-v',
          'threadtime',
        ]);
      }
      if (revision != _sessionRevision || !ref.mounted) {
        process.kill();
        return;
      }
      _process = process;
      _subscription = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine);
      _errorSubscription = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _appendLine('[stderr] $line'));
      process.exitCode.whenComplete(() {
        if (identical(_process, process) && ref.mounted) {
          state = state.copyWith(isRunning: false);
        }
      });
    } on Object catch (error) {
      if (revision == _sessionRevision && ref.mounted) {
        state = state.copyWith(isRunning: false, error: error.toString());
      }
    }
  }

  /// 取消流订阅并终止背后的进程。
  Future<void> stop() async {
    _sessionRevision++;
    await _releaseProcess(updateState: true);
  }

  Future<void> _releaseProcess({required bool updateState}) async {
    _pidMapTimer?.cancel();
    _pidMapTimer = null;
    _batchTimer?.cancel();
    _batchTimer = null;
    _pendingEntries.clear();
    _maxLogLength = 0;
    final subscription = _subscription;
    final errorSubscription = _errorSubscription;
    final process = _process;
    _subscription = null;
    _errorSubscription = null;
    _process = null;
    _deviceId = null;
    process?.kill();
    if (updateState && ref.mounted) {
      state = state.copyWith(isRunning: false);
    }
    await subscription?.cancel();
    await errorSubscription?.cancel();
  }

  /// 清空可见日志缓冲区，但不重启 logcat。
  void clear() {
    _pendingEntries.clear();
    _batchTimer?.cancel();
    _batchTimer = null;
    _maxLogLength = 0;
    state = state.copyWith(entries: []);
  }

  /// 导入 Android Studio 或 adb 导出的文本日志。
  void importText(String text) {
    state = state.copyWith(entries: _parseRecentLines(LineSplitter.split(text)));
  }

  /// 流式导入文件，只保留最近 3000 行，避免同时持有完整文本和解析列表。
  Future<void> importFile(File file) async {
    final lines = readBoundedLogcatLines(
      file.openRead().transform(const Utf8Decoder(allowMalformed: true)),
    );
    final recent = Queue<LogcatEntry>();
    _maxLogLength = 0;
    var processed = 0;
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      recent.add(parseLogcatLine(line, pidPackages: _pidPackages));
      if (recent.length > _maxEntries) recent.removeFirst();
      if (++processed % 500 == 0) await Future<void>.delayed(Duration.zero);
    }
    if (!ref.mounted) return;
    _updateMaxLogLength(recent);
    state = state.copyWith(entries: recent.toList(growable: false));
  }

  List<LogcatEntry> _parseRecentLines(Iterable<String> lines) {
    final recent = Queue<LogcatEntry>();
    _maxLogLength = 0;
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final entry = parseLogcatLine(line, pidPackages: _pidPackages);
      recent.add(entry);
      if (recent.length > _maxEntries) recent.removeFirst();
    }
    _updateMaxLogLength(recent);
    return recent.toList(growable: false);
  }

  void _updateMaxLogLength(Iterable<LogcatEntry> entries) {
    _maxLogLength = 0;
    for (final entry in entries) {
      final length = entry.message.isEmpty ? entry.rawLine.length : entry.message.length;
      if (length > _maxLogLength) _maxLogLength = length;
    }
  }

  /// 更新全文过滤条件。保留旧 API 名称，兼容现有调用。
  void setFilter(String value) => setTextFilter(value);

  void setTextFilter(String value) {
    state = state.copyWith(textFilter: value);
  }

  void setPackageFilter(String value) {
    state = state.copyWith(packageFilter: value);
  }

  void setTagFilter(String value) {
    state = state.copyWith(tagFilter: value);
  }

  Future<void> commitPackageFilter(String value) async {
    await _commitHistory(
      value,
      key: _packageHistoryKey,
      current: state.packageFilterHistory,
      update: (history) => state = state.copyWith(
        packageFilter: value,
        packageFilterHistory: history,
      ),
    );
  }

  Future<void> commitTagFilter(String value) async {
    await _commitHistory(
      value,
      key: _tagHistoryKey,
      current: state.tagFilterHistory,
      update: (history) =>
          state = state.copyWith(tagFilter: value, tagFilterHistory: history),
    );
  }

  Future<void> commitTextFilter(String value) async {
    await _commitHistory(
      value,
      key: _textHistoryKey,
      current: state.textFilterHistory,
      update: (history) =>
          state = state.copyWith(textFilter: value, textFilterHistory: history),
    );
  }

  Future<void> removePackageFilterHistory(String value) async {
    await _removeHistory(
      value,
      key: _packageHistoryKey,
      current: state.packageFilterHistory,
      update: (history) =>
          state = state.copyWith(packageFilterHistory: history),
    );
  }

  Future<void> removeTagFilterHistory(String value) async {
    await _removeHistory(
      value,
      key: _tagHistoryKey,
      current: state.tagFilterHistory,
      update: (history) => state = state.copyWith(tagFilterHistory: history),
    );
  }

  Future<void> removeTextFilterHistory(String value) async {
    await _removeHistory(
      value,
      key: _textHistoryKey,
      current: state.textFilterHistory,
      update: (history) => state = state.copyWith(textFilterHistory: history),
    );
  }

  void setLevelFilter(LogcatLevelFilter value) {
    state = state.copyWith(levelFilter: value);
  }

  void setViewMode(LogcatViewMode value) {
    state = state.copyWith(viewMode: value);
  }

  void togglePaused() {
    state = state.copyWith(isPaused: !state.isPaused);
  }

  void toggleAutoScroll() {
    state = state.copyWith(autoScroll: !state.autoScroll);
  }

  void toggleWrapLines() {
    state = state.copyWith(wrapLines: !state.wrapLines);
  }

  /// 返回过滤后的当前日志缓冲区，供 UI 渲染。
  List<LogcatEntry> visibleEntries() {
    final packageFilter = state.packageFilter.trim().toLowerCase();
    final tagFilter = state.tagFilter.trim().toLowerCase();
    final textFilter = state.textFilter.trim().toLowerCase();
    final minimumPriority = state.levelFilter.minimumLevel.priority;

    return state.entries
        .where((entry) {
          final entryPriority = entry.level.priority;
          if (entryPriority >= 0 && entryPriority < minimumPriority) {
            return false;
          }
          if (packageFilter.isNotEmpty &&
              !entry.packageName.toLowerCase().contains(packageFilter)) {
            return false;
          }
          if (tagFilter.isNotEmpty &&
              !entry.tag.toLowerCase().contains(tagFilter)) {
            return false;
          }
          if (textFilter.isNotEmpty &&
              !entry.searchableText.toLowerCase().contains(textFilter)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  /// 兼容旧 UI/测试的纯文本可见日志。
  List<String> visibleLines() {
    return visibleEntries()
        .map((entry) {
          return switch (state.viewMode) {
            LogcatViewMode.raw => entry.rawLine,
            LogcatViewMode.plain =>
              entry.message.isEmpty ? entry.rawLine : entry.message,
            LogcatViewMode.standard ||
            LogcatViewMode.compact => entry.searchableText,
          };
        })
        .toList(growable: false);
  }

  String exportVisibleText() {
    final entries = visibleEntries();
    return entries.map((entry) => entry.rawLine).join('\n');
  }

  /// 追加一行日志，并只保留最近若干行以控制内存占用。
  void _appendLine(String line) {
    if (state.isPaused) {
      return;
    }
    final boundedLine = line.length > 16384 ? line.substring(0, 16384) : line;
    final entry = parseLogcatLine(boundedLine, pidPackages: _pidPackages);
    final len = entry.message.isEmpty ? entry.rawLine.length : entry.message.length;
    if (len > _maxLogLength) {
      _maxLogLength = len;
    }
    _pendingEntries.add(entry);
    if (_pendingEntries.length > _maxEntries) _pendingEntries.removeFirst();

    _batchTimer ??= Timer(const Duration(milliseconds: 100), () {
      if (_pendingEntries.isEmpty) return;
      final currentEntries = state.entries;
      final next = [...currentEntries, ..._pendingEntries];
      _pendingEntries.clear();
      _batchTimer = null;
      state = state.copyWith(entries: _trimEntries(next));
    });
  }

  List<LogcatEntry> _trimEntries(List<LogcatEntry> entries) {
    if (entries.length <= _maxEntries) {
      return entries;
    }
    return entries.sublist(entries.length - _maxEntries);
  }

  Future<void> _refreshPidPackages() async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      return;
    }
    try {
      final String stdout;
      if (_isHarmony) {
        final result = await Process.run(resolveToolPath('hdc'), [
          '-t',
          deviceId,
          'shell',
          'ps',
          '-ef',
        ]);
        if (result.exitCode != 0) return;
        stdout = result.stdout.toString();
        final mapping = _parseHarmonyPidPackages(stdout);
        if (mapping.isEmpty || deviceId != _deviceId) return;
        _pidPackages = mapping;
      } else {
        final result = await Process.run(resolveToolPath('adb'), [
          '-s',
          deviceId,
          'shell',
          'ps',
          '-A',
          '-o',
          'PID,NAME',
        ]);
        if (result.exitCode != 0) return;
        stdout = result.stdout.toString();
        final mapping = _parsePidPackages(stdout);
        if (mapping.isEmpty || deviceId != _deviceId) return;
        _pidPackages = mapping;
      }
      _applyPidPackagesToExistingEntries();
    } on Object {
      // PID 映射只是辅助字段，失败时不影响实时日志展示。
    }
  }

  /// 解析鸿蒙 `ps -ef` 输出，提取 PID→进程名映射。
  /// 格式：`UID PID PPID C STIME TTY TIME CMD`
  Map<String, String> _parseHarmonyPidPackages(String output) {
    final map = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('UID')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 8) continue;
      final pid = parts[1];
      final cmd = parts.sublist(7).join(' ');
      if (RegExp(r'^\d+$').hasMatch(pid) && cmd.isNotEmpty) {
        map[pid] = cmd;
      }
    }
    return map;
  }

  Map<String, String> _parsePidPackages(String output) {
    final map = <String, String>{};
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('PID ')) {
        continue;
      }
      final match = RegExp(r'^(\d+)\s+(.+)$').firstMatch(trimmed);
      if (match == null) {
        continue;
      }
      map[match.group(1)!] = match.group(2)!.trim();
    }
    return map;
  }

  void _applyPidPackagesToExistingEntries() {
    var changed = false;
    final entries = state.entries
        .map((entry) {
          final packageName = _pidPackages[entry.pid] ?? '';
          if (packageName.isEmpty || entry.packageName == packageName) {
            return entry;
          }
          changed = true;
          return entry.copyWithPackage(packageName);
        })
        .toList(growable: false);
    if (changed) {
      state = state.copyWith(entries: entries);
    }
  }

  Future<void> _loadFilterHistories() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      packageFilterHistory: prefs.getStringList(_packageHistoryKey) ?? const [],
      tagFilterHistory: prefs.getStringList(_tagHistoryKey) ?? const [],
      textFilterHistory: prefs.getStringList(_textHistoryKey) ?? const [],
    );
  }

  Future<void> _commitHistory(
    String value, {
    required String key,
    required List<String> current,
    required void Function(List<String>) update,
  }) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return;
    }
    final next = [
      normalized,
      ...current.where((item) => item != normalized),
    ].take(_maxHistoryItems).toList(growable: false);
    update(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, next);
  }

  Future<void> _removeHistory(
    String value, {
    required String key,
    required List<String> current,
    required void Function(List<String>) update,
  }) async {
    final next = current.where((item) => item != value).toList(growable: false);
    update(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, next);
  }
}
