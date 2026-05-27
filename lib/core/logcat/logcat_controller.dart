import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/tool_path_resolver.dart';
import 'logcat_state.dart';

/// 管理 adb logcat 进程，并暴露有上限的内存日志缓冲区。
class LogcatController extends Notifier<LogcatState> {
  Process? _process;
  StreamSubscription<String>? _subscription;
  StreamSubscription<String>? _errorSubscription;

  @override
  LogcatState build() {
    // Riverpod 销毁控制器时，同步停止外部 logcat 进程。
    ref.onDispose(stop);
    return const LogcatState();
  }

  /// 为选中设备启动新的 logcat 进程。
  Future<void> start(String deviceId, {String level = '*:V'}) async {
    await stop();
    state = state.copyWith(lines: [], isRunning: true);
    try {
      _process = await Process.start(resolveToolPath('adb'), [
        '-s',
        deviceId,
        'logcat',
        level,
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
    await _subscription?.cancel();
    await _errorSubscription?.cancel();
    _subscription = null;
    _errorSubscription = null;
    _process?.kill();
    _process = null;
    state = state.copyWith(isRunning: false);
  }

  /// 清空可见日志缓冲区，但不重启 logcat。
  void clear() {
    state = state.copyWith(lines: []);
  }

  /// 更新 visibleLines 使用的大小写不敏感文本过滤条件。
  void setFilter(String value) {
    state = state.copyWith(filter: value);
  }

  /// 返回过滤后的当前日志缓冲区，供 UI 渲染。
  List<String> visibleLines() {
    final filter = state.filter.trim();
    if (filter.isEmpty) {
      return state.lines;
    }
    final lowerFilter = filter.toLowerCase();
    return state.lines
        .where((line) => line.toLowerCase().contains(lowerFilter))
        .toList(growable: false);
  }

  /// 追加一行日志，并只保留最近 1000 行以控制内存占用。
  void _appendLine(String line) {
    final next = [...state.lines, line];
    if (next.length > 1000) {
      next.removeRange(0, next.length - 1000);
    }
    state = state.copyWith(lines: next);
  }
}
