import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 管理窗口状态和操作；仅在自绘标题栏挂载期间监听系统事件。
class DesktopCaptionController extends ChangeNotifier with WindowListener {
  DesktopCaptionController() {
    windowManager.addListener(this);
    unawaited(refresh());
  }

  bool maximized = false;
  bool focused = true;
  bool fullScreen = false;
  bool busy = false;
  bool _disposed = false;
  int _revision = 0;

  /// 防止连续窗口事件产生的旧查询结果覆盖较新的状态。
  Future<void> refresh() async {
    final revision = ++_revision;
    try {
      final states = await Future.wait([
        windowManager.isMaximized(),
        windowManager.isFocused(),
        windowManager.isFullScreen(),
      ]);
      if (_disposed || revision != _revision) return;
      maximized = states[0];
      focused = states[1];
      fullScreen = states[2];
      notifyListeners();
    } catch (error) {
      debugPrint('Window caption state unavailable: $error');
    }
  }

  Future<void> minimize() => _run(windowManager.minimize);

  Future<void> toggleMaximized() => _run(() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  });

  /// 走原生 close 事件，沿用主窗口的隐藏到托盘与子窗口清理策略。
  Future<void> close() => _run(windowManager.close);

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    notifyListeners();
    try {
      await action();
      await refresh();
    } catch (error) {
      debugPrint('Window caption action failed: $error');
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (const {
      'maximize',
      'unmaximize',
      'restore',
      'focus',
      'blur',
      'enter-full-screen',
      'leave-full-screen',
    }.contains(eventName)) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    super.dispose();
  }
}
