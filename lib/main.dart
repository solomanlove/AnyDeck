import 'dart:convert';
import 'dart:ui';
import 'dart:isolate';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/adb_manage_app.dart';
import 'app/window/desktop_window_manager_service.dart';
import 'app/window/emulator/emulator_manager_window_app.dart';
import 'app/window/mirror/mirror_window_app.dart';
import 'app/window/multi_window_compat.dart';

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

  //如果是多窗口
  if (args.firstOrNull == 'multi_window') {
    //打印下日志
    debugPrint('多窗口参数$args');
    final windowId = args[1];
    final Map<String, dynamic> argument;
    if (args[2].isEmpty) {
      argument = const <String, dynamic>{};
    } else if (args[2].startsWith('{')) {
      argument = jsonDecode(args[2]) as Map<String, dynamic>;
    } else {
      argument = <String, dynamic>{};
      for (final part in args[2].split('&')) {
        final kv = part.split('=');
        if (kv.length == 2) {
          argument[Uri.decodeComponent(kv[0])] = Uri.decodeComponent(kv[1]);
        }
      }
    }

    final type = argument['type'] as String?;
    final windowName = type == 'mirror'
        ? 'mirror_window_$windowId'
        : 'emulator_window_$windowId';
    PlatformDispatcher.instance.setIsolateDebugName(windowName);

    // 获取当前子窗口 of VM Service URI 和 Isolate ID 并输出，用于在 DevTools 中连接调试
    developer.Service.getInfo().then((info) {
      final uri = info.serverUri;
      if (uri != null) {
        final isolateId = developer.Service.getIsolateId(Isolate.current);
        if (isolateId != null) {
          final encodedUri = Uri.encodeComponent(uri.toString());
          final encodedIsolateId = Uri.encodeComponent(isolateId);
          debugPrint(
            '\n======================================================',
          );
          debugPrint('[$windowName] Sub-window Isolate Info:');
          debugPrint('Isolate Name: $windowName');
          debugPrint('Isolate ID: $isolateId');
          debugPrint('VM Service URI: $uri');
          debugPrint(
            '\nConstructed DevTools Link (assuming default port 9100):',
          );
          debugPrint(
            'http://127.0.0.1:9100/#/inspector?uri=$encodedUri&isolateId=$encodedIsolateId',
          );
          debugPrint(
            '\n*(Note: If your DevTools port is not 9100, replace "127.0.0.1:9100" in the link above with the actual DevTools port from your browser)*',
          );
          debugPrint(
            '======================================================\n',
          );
        }
      }
    });

    if (type == 'mirror') {
      await configureCurrentAdbManageSubWindow(argument);
      //投屏窗口
      runApp(
        ProviderScope(
          overrides: [windowIdProvider.overrideWithValue(windowId)],
          child: MirrorWindowApp(windowId: windowId, argument: argument),
        ),
      );
    } else {
      await configureCurrentAdbManageSubWindow(argument);
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
