import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/adb_manage_app.dart';
import 'app/window/desktop_window_manager_service.dart';
import 'app/window/emulator/emulator_manager_window_app.dart';
import 'app/window/mirror/mirror_window_app.dart';

import 'app/settings/app_settings_controller.dart';

/// 应用入口，ProviderScope 负责承载全局 Riverpod 依赖图。
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // 修复在 macOS/桌面端因焦点切换或系统合成事件导致的 KeyUpEvent 断言 crash 错误。
  // 当 Flutter 接收到 KeyUpEvent，但其内部 HardwareKeyboard 并没有记录对应的 KeyDownEvent 时，
  // 拦截并丢弃该事件以防止在 Debug 模式下抛出 AssertionError 导致红屏或崩溃。
  final originalOnKeyData = PlatformDispatcher.instance.onKeyData;
  PlatformDispatcher.instance.onKeyData = (KeyData data) {
    try {
      final dynamic binding = ServicesBinding.instance;
      final dynamic manager = binding.keyEventManager;
      if (manager.transitMode.toString().endsWith('rawKeyData')) {
        return false;
      }
    } catch (_) {}
    if (data.type == KeyEventType.up) {
      final physicalKey = PhysicalKeyboardKey(data.physical);
      if (!HardwareKeyboard.instance.physicalKeysPressed.contains(
        physicalKey,
      )) {
        debugPrint(
          '[KeyAssertionFix] Suppressed mismatched KeyUpEvent for physicalKey: $physicalKey',
        );
        return true; // 返回 true 表示事件已消费，不再向下游分发
      }
    }
    return originalOnKeyData?.call(data) ?? false;
  };

  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args[2].isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(args[2]) as Map<String, dynamic>;

    final type = argument['type'] as String?;
    if (type == 'mirror') {
      //投屏窗口
      runApp(
        ProviderScope(
          overrides: [windowIdProvider.overrideWithValue(windowId)],
          child: MirrorWindowApp(windowId: windowId, argument: argument),
        ),
      );
    } else {
      //模拟器管理窗口
      runApp(
        ProviderScope(
          overrides: [windowIdProvider.overrideWithValue(windowId)],
          child: EmulatorManagerWindowApp(
            windowId: windowId,
            argument: argument,
          ),
        ),
      );
    }
    return;
  }

  await DesktopWindowManagerService.initialize();
  //主窗口
  runApp(const ProviderScope(child: AdbManageApp()));
}
