import 'dart:async';
import 'dart:collection';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../shortcuts/window_shortcut.dart';

/// 子窗口通过单向 Channel 请求主窗口打开设置或执行退出快捷键流程。
/// 关闭窗口始终留在当前引擎；注册 / 注销串行执行，防止主窗口重建时覆盖新回调。
class WindowShortcutBridge {
  static const channelName = 'any_deck/window_shortcuts';
  static const _channel = WindowMethodChannel(
    channelName,
    mode: ChannelMode.unidirectional,
  );
  static Object? _owner;
  static final _queue =
      Queue<
        ({Future<void> Function() operation, Completer<void> completion})
      >();
  static bool _draining = false;

  /// 等待已排队的注册 / 注销完成，供窗口资源回收时协调。
  static Future<void> get settled => _enqueue(() async {});

  static Future<void> _enqueue(Future<void> Function() operation) {
    final completion = Completer<void>();
    _queue.add((operation: operation, completion: completion));
    if (!_draining) unawaited(_drain());
    return completion.future;
  }

  /// 仅保留待执行任务，完成后释放闭包与旧窗口引用，不保留已完成的 Future 链。
  static Future<void> _drain() async {
    _draining = true;
    while (_queue.isNotEmpty) {
      final task = _queue.removeFirst();
      try {
        await task.operation();
        task.completion.complete();
      } catch (error, stack) {
        task.completion.completeError(error, stack);
      }
    }
    _draining = false;
  }

  static Future<void> register(
    Object owner,
    Future<void> Function(WindowShortcut action) handler,
  ) {
    _owner = owner;
    return _enqueue(
      () => _channel.setMethodCallHandler((call) async {
        if (_owner != owner ||
            call.method != 'perform' ||
            call.arguments is! String) {
          return null;
        }
        final action = WindowShortcut.values
            .where((action) => action.name == call.arguments)
            .firstOrNull;
        if (action == null || action == WindowShortcut.closeWindow) return null;
        await handler(action);
        return null;
      }),
    );
  }

  static Future<void> unregister(Object owner) {
    if (_owner != owner) return Future.value();
    _owner = null;
    return _enqueue(() async {
      if (_owner == null) await _channel.setMethodCallHandler(null);
    });
  }

  static Future<void> request(WindowShortcut action) {
    if (action == WindowShortcut.closeWindow) {
      throw ArgumentError.value(action, 'action');
    }
    return _channel
        .invokeMethod<void>('perform', action.name)
        .timeout(const Duration(seconds: 5));
  }
}
