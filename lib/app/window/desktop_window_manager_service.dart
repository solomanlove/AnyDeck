import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/app/l10n/app_localized_values.dart';
import 'package:any_deck/app/window/multi_window_compat.dart';
import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/features/mcp/controller/mcp_server_controller.dart';

/// 桌面端窗口与系统托盘管理服务。
class DesktopWindowManagerService {
  DesktopWindowManagerService._();

  static final _trayListener = _AppTrayListener();
  static final _windowListener = _AppWindowListener();

  static ProviderContainer? _providerContainer;
  static bool _isMcpRunning = false;
  static String _currentLangCode = 'zh';

  /// 关联全局 Riverpod ProviderContainer 并实时同步 MCP 状态到系统托盘
  static void setProviderContainer(ProviderContainer container) {
    _providerContainer = container;
    container.listen<McpServerState>(mcpServerProvider, (previous, next) {
      if (_isMcpRunning != next.isRunning) {
        _isMcpRunning = next.isRunning;
        updateTrayMenu(_currentLangCode, isMcpRunning: _isMcpRunning);
      }
    });
    _isMcpRunning = container.read(mcpServerProvider).isRunning;
    updateTrayMenu(_currentLangCode, isMcpRunning: _isMcpRunning);
  }

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
      await windowManager.setPreventClose(true); // 拦截关闭事件，最小化到托盘
    });

    // 2. 初始化 tray_manager (系统托盘)
    try {
      await trayManager.setIcon(AppIcons.appTrayIcon, isTemplate: Platform.isMacOS, iconSize: 18);

      String langCode = 'zh';
      try {
        final preferences = await SharedPreferences.getInstance();
        final savedCode = preferences.getString('settings.language');
        if (savedCode == 'en' || savedCode == 'zh') {
          langCode = savedCode!;
        }
      } catch (_) {}
      _currentLangCode = langCode;

      await updateTrayMenu(langCode, isMcpRunning: _isMcpRunning);
      trayManager.addListener(_trayListener);
    } catch (e) {
      debugPrint('Tray initialization failed: $e');
    }
  }

  /// 显示主窗口并获取焦点（在首帧渲染就绪后调用，消除启动黑屏）。
  static Future<void> showWindow() async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;
    await windowManager.show();
    await windowManager.focus();
  }

  /// 动态更新托盘菜单语言与 MCP 运行状态。
  static Future<void> updateTrayMenu(String langCode, {bool? isMcpRunning}) async {
    if (kIsWeb || Platform.isAndroid || Platform.isIOS) return;

    if (isMcpRunning != null) {
      _isMcpRunning = isMcpRunning;
    }
    _currentLangCode = langCode;

    try {
      final showLabel = localizedValues[langCode]?['trayShowWindow'] ?? (langCode == 'en' ? 'Show Window' : '显示窗口');
      final exitLabel = localizedValues[langCode]?['trayExit'] ?? (langCode == 'en' ? 'Exit' : '退出');
      final emulatorsLabel = langCode == 'en' ? 'Emulator Manager Window' : '模拟器管理窗口';
      final consoleLabel = langCode == 'en' ? 'Console Window' : '控制台窗口';
      final mcpToggleLabel = _isMcpRunning
          ? (langCode == 'en' ? 'Stop MCP Service' : '停止 MCP 服务')
          : (langCode == 'en' ? 'Start MCP Service' : '启动 MCP 服务');

      final menuItems = [
        MenuItem(key: 'show_window', label: showLabel),
        MenuItem(key: 'open_emulators', label: emulatorsLabel),
        MenuItem(key: 'open_console', label: consoleLabel),
        MenuItem.separator(),
        MenuItem(key: 'toggle_mcp', label: mcpToggleLabel),
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
    } else if (menuItem.key == 'open_emulators') {
      String langCode = 'zh';
      try {
        final preferences = await SharedPreferences.getInstance();
        final savedCode = preferences.getString('settings.language');
        if (savedCode == 'en' || savedCode == 'zh') {
          langCode = savedCode!;
        }
      } catch (_) {}
      await createAdbManageWindow(
        arguments: const {'type': 'emulator_manager'},
        frame: const Offset(100, 100) & const Size(900, 600),
        title: langCode == 'en' ? 'Emulators' : '模拟器管理',
      );
    } else if (menuItem.key == 'open_console') {
      String langCode = 'zh';
      try {
        final preferences = await SharedPreferences.getInstance();
        final savedCode = preferences.getString('settings.language');
        if (savedCode == 'en' || savedCode == 'zh') {
          langCode = savedCode!;
        }
      } catch (_) {}
      await createAdbManageWindow(
        arguments: const {'type': 'console'},
        frame: const Offset(150, 150) & const Size(850, 550),
        title: langCode == 'en' ? 'Console' : '控制台',
      );
    } else if (menuItem.key == 'toggle_mcp') {
      final container = DesktopWindowManagerService._providerContainer;
      if (container != null) {
        final isRunning = container.read(mcpServerProvider).isRunning;
        final notifier = container.read(mcpServerProvider.notifier);
        if (isRunning) {
          await notifier.stopServer();
        } else {
          await notifier.startServer();
        }
      }
    } else if (menuItem.key == 'exit_app') {
      // 退出应用时需要先解除关闭拦截，否则无法 destroy 窗口
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
      exit(0);
    }
  }
}

class _AppWindowListener extends WindowListener {}
