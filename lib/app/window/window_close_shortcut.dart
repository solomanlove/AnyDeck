import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// 为独立子窗口提供 macOS 标准关闭快捷键。
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
