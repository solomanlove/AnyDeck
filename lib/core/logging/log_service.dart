import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/app_settings_controller.dart';
import '../../app/window/sub_window_method_dispatcher.dart';
import 'app_log_recorder.dart';

/// 控制台日志状态，主窗口汇总各 Isolate 的运行日志和命令记录。
final logHistoryProvider = NotifierProvider<LogService, List<String>>(
  LogService.new,
);

/// 以有界队列和批量广播连接本地采集器与控制台，避免逐条枚举窗口。
class LogService extends Notifier<List<String>> {
  static const _logChannel = WindowMethodChannel(
    'any_deck/console_logs',
    mode: ChannelMode.unidirectional,
  );
  static const _timeout = Duration(seconds: 2);
  final List<String> _pending = [];
  Timer? _timer;
  bool _sending = false;
  bool get _isMain => ref.read(windowIdProvider).isEmpty;

  @override
  List<String> build() {
    final recorder = AppLogRecorder.instance;
    final isMain = _isMain;
    final subscription = recorder.events.listen(_enqueue);
    if (_isMain) {
      // 注册失败时仅保留本地记录，禁止 debugPrint 引发日志反馈循环。
      unawaited(
        _logChannel.setMethodCallHandler(_handleLogCall).catchError((_) {}),
      );
    } else {
      SubWindowMethodDispatcher.registerHandler(_handleLogCall);
      // 子窗口在 Provider 建立前的启动日志也需要转发。
      for (final line in recorder.history) {
        _enqueue(line);
      }
    }
    ref.onDispose(() {
      _timer?.cancel();
      unawaited(subscription.cancel());
      if (!isMain) SubWindowMethodDispatcher.removeHandler(_handleLogCall);
    });
    return recorder.history;
  }

  Future<dynamic> _handleLogCall(MethodCall call) async {
    if (!ref.mounted) return null;
    switch (call.method) {
      case 'flush_local_logs':
        await AppLogRecorder.instance.store?.flush();
        return AppLogRecorder.instance.store != null &&
            AppLogRecorder.instance.store?.lastError == null &&
            AppLogRecorder.instance.store?.lostRecords == 0;
      case 'log_batch':
        _addLocal(_readBatch(call.arguments));
      case 'log':
        if (call.arguments is String) _addLocal([call.arguments as String]);
      case 'log_batch_from_sub':
        for (final line in _readBatch(call.arguments)) {
          _enqueue(line);
        }
      case 'log_from_sub':
        if (call.arguments is String) _enqueue(call.arguments as String);
      case 'get_history':
        return _bounded([...state, ..._pending]);
      case 'clear':
        _pending.clear();
        state = [];
      case 'clear_from_sub':
        clear();
    }
    return null;
  }

  List<String> _readBatch(dynamic value) => value is List
      ? value.whereType<String>().take(AppLogRecorder.maxRecords).toList()
      : [];

  /// 对外保留命令服务已有的日志接口，由采集器统一持久化和脱敏。
  void log(String message, {String tag = 'adb', String level = 'I'}) {
    AppLogRecorder.instance.record(message, tag: tag, level: level);
  }

  void _enqueue(String line) {
    _pending.add(line);
    if (_pending.length > AppLogRecorder.maxRecords) _pending.removeAt(0);
    _schedule();
  }

  void _schedule() {
    if (_sending || _timer != null) return;
    _timer = Timer(const Duration(milliseconds: 150), () {
      _timer = null;
      unawaited(_flushBatch());
    });
  }

  Future<void> _flushBatch() async {
    if (!ref.mounted || _pending.isEmpty) return;
    _sending = true;
    final batch = List<String>.from(_pending);
    _pending.clear();
    _addLocal(batch);
    try {
      if (_isMain) {
        await _broadcast('log_batch', batch);
      } else {
        await _logChannel
            .invokeMethod('log_batch_from_sub', batch)
            .timeout(_timeout);
      }
    } catch (_) {
      // 主窗口未启动或已经关闭时，子窗口仍有本地内存及文件记录。
    } finally {
      _sending = false;
      if (ref.mounted && _pending.isNotEmpty) _schedule();
    }
  }

  /// 清空当前显示，不删除故障排查所需的本地日志文件。
  void clear() {
    _pending.clear();
    state = [];
    if (_isMain) {
      unawaited(_broadcast('clear', null));
    } else {
      unawaited(
        _logChannel
            .invokeMethod('clear_from_sub')
            .timeout(_timeout)
            .catchError((_) => null),
      );
    }
  }

  Future<void> _broadcast(String method, dynamic arguments) async {
    try {
      final windows = await WindowController.getAll().timeout(_timeout);
      await Future.wait(
        windows.map((window) async {
          try {
            if (window.arguments.isEmpty) return;
            final args = jsonDecode(window.arguments);
            if (args is Map && args['type'] == 'console') {
              await window.invokeMethod(method, arguments).timeout(_timeout);
            }
          } catch (_) {
            // 窗口销毁、参数损坏和 dead channel 均不阻塞其他控制台。
          }
        }),
      );
    } catch (_) {
      // 通信错误不可回流采集器，避免递归广播。
    }
  }

  List<String> _bounded(List<String> lines) =>
      lines.length > AppLogRecorder.maxRecords
      ? lines.sublist(lines.length - AppLogRecorder.maxRecords)
      : lines;

  void _addLocal(List<String> lines) {
    if (!ref.mounted) return;
    // 历史同步和实时广播可能交错，时间戳含微秒用于去重。
    state = _bounded({...state, ...lines}.toList());
  }

  /// 控制台启动时读取主窗口快照，同时保留同步期间收到的新日志。
  Future<void> syncHistory() async {
    if (_isMain) return;
    try {
      final history = await _logChannel
          .invokeMethod('get_history')
          .timeout(_timeout);
      if (!ref.mounted) return;
      state = _bounded({..._readBatch(history), ...state}.toList()..sort());
    } catch (_) {
      // 脚本直启控制台时展示当前 Isolate 的本地日志。
    }
  }
}
