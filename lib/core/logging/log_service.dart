import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../../app/settings/app_settings_controller.dart';

/// 全局日志历史提供者，维护一个字符串日志列表。
final logHistoryProvider = NotifierProvider<LogService, List<String>>(LogService.new);

/// 日志服务类，负责收集 adb 命令执行记录并提供跨多窗口通信广播。
class LogService extends Notifier<List<String>> {
  static const _logChannel = WindowMethodChannel(
    'any_deck/console_logs',
    mode: ChannelMode.unidirectional,
  );

  @override
  List<String> build() {
    _setupLogChannel();
    return [];
  }

  /// 注册窗口方法调用处理器以接收其他 Isolate 发来的日志。
  void _setupLogChannel() {
    final currentId = ref.read(windowIdProvider);
    if (currentId.isEmpty) {
      // 主窗口注册单向通道监听，用来处理子窗口的日志上报与历史同步请求
      unawaited(_logChannel.setMethodCallHandler(_handleLogCall));
      return;
    }

    // 子窗口则监听主Isolate通过 `WindowController.invokeMethod` 广播进来的日志数据
    unawaited(
      WindowController.fromCurrentEngine().then((controller) {
        return controller.setWindowMethodHandler(_handleLogCall);
      }).catchError((e) {
        debugPrint('Failed to register sub-window log handler: $e');
      }),
    );
  }

  /// 处理跨 Isolate 消息的回调。
  Future<dynamic> _handleLogCall(MethodCall call) async {
    if (call.method == 'log') {
      // 子窗口接收到主窗口广播的单条日志
      final logMsg = call.arguments as String;
      state = [...state, logMsg];
    } else if (call.method == 'log_from_sub') {
      // 主窗口接收到子窗口发送的日志，进行处理并广播
      final logMsg = call.arguments as String;
      _addAndBroadcastLog(logMsg);
    } else if (call.method == 'get_history') {
      // 主窗口接收到子窗口的历史同步请求，返回当前的全部日志
      return state;
    } else if (call.method == 'clear') {
      // 子窗口接收到主窗口发送的清空指令
      state = [];
    } else if (call.method == 'clear_from_sub') {
      // 主窗口接收到子窗口的清空请求，本地清空并向所有窗口广播
      _clearAndBroadcast();
    }
    return null;
  }

  /// 记录一条格式化日志，并自动进行跨窗口同步。
  void log(String message, {String tag = 'adb', String level = 'I'}) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final logMsg = '$timeStr $level $tag: $message';

    final currentId = ref.read(windowIdProvider);
    if (currentId.isNotEmpty) {
      // 子窗口不直接维护日志状态，而是通过单向通道调用主窗口来汇总
      _logChannel.invokeMethod('log_from_sub', logMsg);
    } else {
      // 主窗口直接本地记录并向所有子窗口发起广播
      _addAndBroadcastLog(logMsg);
    }
  }

  /// 清空所有日志
  void clear() {
    final currentId = ref.read(windowIdProvider);
    if (currentId.isNotEmpty) {
      _logChannel.invokeMethod('clear_from_sub');
    } else {
      _clearAndBroadcast();
    }
  }

  /// 仅在主窗口执行：清空本地日志并广播给所有子窗口
  void _clearAndBroadcast() async {
    state = [];
    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments.isEmpty) continue;
        try {
          final args = jsonDecode(window.arguments);
          if (args is Map && args['type'] == 'console') {
            await window.invokeMethod('clear');
          }
        } catch (e) {
          // ignore
        }
      }
    } catch (e) {
      debugPrint('Failed to broadcast clear: $e');
    }
  }

  /// 仅在主窗口执行：将日志持久存储到状态中并向所有子窗口（控制台）分发。
  void _addAndBroadcastLog(String logMsg) async {
    // 限制最大日志量为 1000 条，防止长时间运行导致内存泄漏
    var newLogs = [...state, logMsg];
    if (newLogs.length > 1000) {
      newLogs = newLogs.sublist(newLogs.length - 1000);
    }
    state = newLogs;

    try {
      final windows = await WindowController.getAll();
      for (final window in windows) {
        if (window.arguments.isEmpty) continue;
        try {
          final args = jsonDecode(window.arguments);
          if (args is Map && args['type'] == 'console') {
            // 通过 windowId 对应的控制器调用子Isolate的方法
            await window.invokeMethod('log', logMsg);
          }
        } catch (e) {
          // 忽略个别窗口解析参数失败的情况
        }
      }
    } catch (e) {
      debugPrint('Failed to broadcast log: $e');
    }
  }

  /// 在控制台子窗口启动时，向主窗口拉取所有已记录的历史日志。
  Future<void> syncHistory() async {
    final currentId = ref.read(windowIdProvider);
    if (currentId.isEmpty) return; // 仅子窗口需要同步

    try {
      final history = await _logChannel.invokeMethod('get_history');
      if (history is List) {
        state = List<String>.from(history);
      }
    } catch (e) {
      debugPrint('Failed to sync log history: $e');
    }
  }
}
