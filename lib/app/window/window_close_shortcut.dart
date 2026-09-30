import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// 为独立子窗口提供 macOS 标准关闭快捷键（⌘W）。
class WindowCloseShortcut extends StatelessWidget {
  const WindowCloseShortcut({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
            windowManager.close,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// 为主窗口提供 macOS 标准快捷键：
/// - ⌘W：走 close listener（最小化到托盘）
/// - ⌘Q（macOS）：退出整个应用
/// - ⌘[showWindowKey]：显示并聚焦主窗口（默认 ⌘1）
class MainWindowCloseShortcut extends StatelessWidget {
  const MainWindowCloseShortcut({
    super.key,
    required this.child,
    this.showWindowKey = '1',
    this.onQuit,
  });

  final Widget child;

  /// 显示主窗口的按键字符（单字符，默认 '1'）
  final String showWindowKey;

  /// 退出快捷键回调（若提供则委托，支持双按退出确认）
  final VoidCallback? onQuit;

  /// 将字符串 key 映射到 LogicalKeyboardKey
  static LogicalKeyboardKey? _keyFromChar(String char) {
    switch (char.toLowerCase()) {
      case '1': return LogicalKeyboardKey.digit1;
      case '2': return LogicalKeyboardKey.digit2;
      case '3': return LogicalKeyboardKey.digit3;
      case '4': return LogicalKeyboardKey.digit4;
      case '5': return LogicalKeyboardKey.digit5;
      case 'a': return LogicalKeyboardKey.keyA;
      case 'b': return LogicalKeyboardKey.keyB;
      case 'd': return LogicalKeyboardKey.keyD;
      case 'e': return LogicalKeyboardKey.keyE;
      case 'm': return LogicalKeyboardKey.keyM;
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
          windowManager.close,
    };

    // macOS 上注册 ⌘Q 退出整个应用（与状态栏退出一致）
    if (Platform.isMacOS) {
      if (onQuit != null) {
        bindings[const SingleActivator(LogicalKeyboardKey.keyQ, meta: true)] =
            onQuit!;
      } else {
        bindings[const SingleActivator(LogicalKeyboardKey.keyQ, meta: true)] =
            () async {
          await windowManager.setPreventClose(false);
          await windowManager.destroy();
          exit(0);
        };
      }
    }

    // 注册动态显示主窗口快捷键（默认 ⌘1）
    final showKey = _keyFromChar(showWindowKey);
    if (showKey != null) {
      bindings[SingleActivator(showKey, meta: true)] = () async {
        await windowManager.show();
        await windowManager.focus();
      };
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}
