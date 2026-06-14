import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/app/l10n/app_localized_values.dart';

/// 桌面端窗口与系统托盘管理服务。
class DesktopWindowManagerService {
  DesktopWindowManagerService._();

  static final _trayListener = _AppTrayListener();
  static final _windowListener = _AppWindowListener();

  /// 初始化窗口管理器和系统托盘。
  static Future<void> initialize() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;

    WidgetsFlutterBinding.ensureInitialized();

    // 1. 初始化 window_manager
    await windowManager.ensureInitialized();
    windowManager.addListener(_windowListener);

    const windowOptions = WindowOptions(
      size: Size(1100, 780),// 初始窗口大小
      minimumSize: Size(700, 400), // 限制最小窗口尺寸
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 隐藏原生标题栏
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true); // 拦截关闭事件，最小化到托盘
    });

    // 2. 初始化 tray_manager (系统托盘)
    try {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/brand/app_logo.png'
            : 'assets/brand/app_logo.png',
      );

      String langCode = 'zh';
      try {
        final preferences = await SharedPreferences.getInstance();
        final savedCode = preferences.getString('settings.language');
        if (savedCode == 'en' || savedCode == 'zh') {
          langCode = savedCode!;
        }
      } catch (_) {}

      final showLabel = localizedValues[langCode]?['trayShowWindow'] ?? (langCode == 'en' ? 'Show Window' : '显示窗口');
      final exitLabel = localizedValues[langCode]?['trayExit'] ?? (langCode == 'en' ? 'Exit' : '退出');

      final menuItems = [
        MenuItem(key: 'show_window', label: showLabel),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: exitLabel),
      ];
      await trayManager.setContextMenu(Menu(items: menuItems));
      trayManager.addListener(_trayListener);
    } catch (e) {
      debugPrint('Tray initialization failed: $e');
    }
  }

  /// 动态更新托盘菜单语言。
  static Future<void> updateTrayMenu(String langCode) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;

    try {
      final showLabel = localizedValues[langCode]?['trayShowWindow'] ?? (langCode == 'en' ? 'Show Window' : '显示窗口');
      final exitLabel = localizedValues[langCode]?['trayExit'] ?? (langCode == 'en' ? 'Exit' : '退出');

      final menuItems = [
        MenuItem(key: 'show_window', label: showLabel),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: exitLabel),
      ];
      await trayManager.setContextMenu(Menu(items: menuItems));
    } catch (e) {
      debugPrint('Tray update failed: $e');
    }
  }

  /// 释放监听器。
  static void dispose() {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    trayManager.removeListener(_trayListener);
    windowManager.removeListener(_windowListener);
  }
}

class _AppTrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() async {
    // 点击托盘图标显示并聚焦窗口
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键托盘图标弹出上下文菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      // 退出应用时需要先解除关闭拦截，否则无法 destroy 窗口
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    }
  }
}

class _AppWindowListener extends WindowListener {}
