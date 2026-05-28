import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../process/tool_path_resolver.dart';
import 'logcat_entry.dart';
import 'logcat_state.dart';

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
  Map<String, String> _pidPackages = const {};

  @override
  LogcatState build() {
    // Riverpod 销毁控制器时，同步停止外部 logcat 进程。
    ref.onDispose(() {
      unawaited(_releaseProcess(updateState: false));
    });
    unawaited(_loadFilterHistories());
    return const LogcatState();
  }

  /// 为选中设备启动新的 logcat 进程。
  Future<void> start(String deviceId) async {
    await stop();
    _deviceId = deviceId;
    state = state.copyWith(entries: [], isRunning: true, isPaused: false);
    try {
      await _refreshPidPackages();
      _pidMapTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _refreshPidPackages(),
      );
      _process = await Process.start(resolveToolPath('adb'), [
        '-s',
        deviceId,
        'logcat',
        '-v',
        'threadtime',
      ]);
      _subscription = _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_appendLine);
      _errorSubscription = _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) => _appendLine('[stderr] $line'));
      _process!.exitCode.whenComplete(() {
        if (_process != null) {
          state = state.copyWith(isRunning: false);
        }
      });
    } on Object catch (error) {
      state = state.copyWith(isRunning: false, error: error.toString());
    }
  }

  /// 取消流订阅并终止背后的进程。
  Future<void> stop() async {
    await _releaseProcess(updateState: true);
  }

  Future<void> _releaseProcess({required bool updateState}) async {
    _pidMapTimer?.cancel();
    _pidMapTimer = null;
    await _subscription?.cancel();
    await _errorSubscription?.cancel();
    _subscription = null;
    _errorSubscription = null;
    _process?.kill();
    _process = null;
    _deviceId = null;
    if (updateState) {
      state = state.copyWith(isRunning: false);
    }
  }

  /// 清空可见日志缓冲区，但不重启 logcat。
  void clear() {
    state = state.copyWith(entries: []);
  }

  /// 导入 Android Studio 或 adb 导出的文本日志。
  void importText(String text) {
    final entries = const LineSplitter()
        .convert(text)
        .where((line) => line.trim().isNotEmpty)
        .map((line) => parseLogcatLine(line, pidPackages: _pidPackages))
        .toList(growable: false);
    state = state.copyWith(entries: _trimEntries(entries));
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
    final entry = parseLogcatLine(line, pidPackages: _pidPackages);
    final next = _trimEntries([...state.entries, entry]);
    state = state.copyWith(entries: next);
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
      final result = await Process.run(resolveToolPath('adb'), [
        '-s',
        deviceId,
        'shell',
        'ps',
        '-A',
        '-o',
        'PID,NAME',
      ]);
      if (result.exitCode != 0) {
        return;
      }
      final mapping = _parsePidPackages(result.stdout.toString());
      if (mapping.isEmpty) {
        return;
      }
      _pidPackages = mapping;
      _applyPidPackagesToExistingEntries();
    } on Object {
      // PID 映射只是辅助字段，失败时不影响实时日志展示。
    }
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
