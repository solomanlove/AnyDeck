import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../../features/dashboard/presentation/control/embedded_scrcpy_viewer.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../features/dashboard/presentation/widgets/drag_drop_target_overlay.dart';
import 'mirror_floating_toolbar.dart';
import 'mirror_settings_dialog.dart';
import 'mirror_window_controller.dart';

/// 投屏独立窗口应用入口。
class MirrorWindowApp extends ConsumerWidget {
  const MirrorWindowApp({
    super.key,
    required this.windowId,
    required this.argument,
  });

  final String windowId;
  final Map<String, dynamic> argument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final deviceId = argument['deviceId'] as String? ?? '';
    final deviceName = argument['deviceName'] as String? ?? 'Device';
    final newDisplay = argument['newDisplay'] as String?;
    final startApp = argument['startApp'] as String?;

    return MaterialApp(
      onGenerateTitle: (context) => deviceName,
      debugShowCheckedModeBanner: false,
      locale: settings.language.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: settings.themeMode,
      home: MirrorWindowContent(
        deviceId: deviceId,
        deviceName: deviceName,
        windowId: windowId,
        newDisplay: newDisplay,
        startApp: startApp,
      ),
    );
  }
}

/// 投屏独立窗口内容组件，继承自 ConsumerStatefulWidget 以支持 Riverpod。
class MirrorWindowContent extends ConsumerStatefulWidget {
  const MirrorWindowContent({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.windowId,
    this.newDisplay,
    this.startApp,
  });

  final String deviceId;
  final String deviceName;
  final String windowId;
  final String? newDisplay;
  final String? startApp;

  @override
  ConsumerState<MirrorWindowContent> createState() =>
      _MirrorWindowContentState();
}

/// 投屏窗口的 UI 状态类，混入 WindowListener 以响应桌面窗口交互事件。
class _MirrorWindowContentState extends ConsumerState<MirrorWindowContent>
    with WindowListener {
  
  /// 投屏业务控制器
  late final MirrorWindowController _controller;
  
  /// 用于捕获键盘事件的 FocusNode
  late final FocusNode _keyboardFocusNode;
  
  /// 记录上一次鼠标按下的时间，用于辅助判定双击事件
  DateTime? _lastPointerDownTime;
  
  /// 用于获取投屏窗口实际渲染尺寸的 Key
  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(debugLabel: 'MirrorWindowKeyboard');

    // 实例化业务逻辑控制器
    _controller = MirrorWindowController(
      ref: ref,
      deviceId: widget.deviceId,
      windowId: widget.windowId,
      newDisplay: widget.newDisplay,
      startApp: widget.startApp,
    );

    // 监听控制器状态变化，更新 UI
    _controller.addListener(_onControllerChanged);

    // 非 macOS 平台需要注册窗口监听器
    if (!Platform.isMacOS) {
      windowManager.addListener(this);
    }

    // 初始化控制器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.init(_viewerKey);
    });
  }

  @override
  void dispose() {
    // 移除监听并释放控制器资源
    _controller.removeListener(_onControllerChanged);
    _controller.disposeController();

    if (!Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  /// 监听控制器属性变动时的回调
  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ==================== WindowListener 接口实现 ====================

  @override
  void onWindowEnterFullScreen() {
    _controller.onWindowEnterFullScreen();
  }

  @override
  void onWindowLeaveFullScreen() {
    _controller.onWindowLeaveFullScreen();
  }

  // ==================== 界面渲染 (UI Build) ====================

  @override
  Widget build(BuildContext context) {
    final textureId = ref.watch(activeEmbeddedMirrorProvider(widget.deviceId));
    final isMirrorActive = textureId != null;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final headerBgColor = isDark
        ? Theme.of(context).cardColor
        : const Color(0xffffffff);
    final borderColor = isDark
        ? const Color(0xff2d2d2d)
        : const Color(0xffeceef1);

    // 根据控制器状态组装核心内容区域
    Widget contentWidget;
    if (_controller.isLoading) {
      contentWidget = const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在启动投屏服务...', style: TextStyle(fontSize: 14)),
          ],
        ),
      );
    }
    else if (_controller.errorMessage != null) {
      contentWidget = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                '投屏启动失败',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _controller.errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _controller.startMirroring,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    else if (isMirrorActive) {
      contentWidget = Column(
        children: [
          // 非全屏且非单应用模式下，展示顶部浮动操作栏
          if (!_controller.isFullScreen && widget.startApp == null)
            SizedBox(
              width: double.infinity,
              child: MirrorFloatingToolbar(
                deviceId: widget.deviceId,
                windowId: widget.windowId,
              ),
            ),
          Expanded(
            child: ClipRRect(
              child: Listener(
                key: _viewerKey,
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  final now = DateTime.now();
                  // 判定双击
                  if (_lastPointerDownTime != null &&
                      now.difference(_lastPointerDownTime!) <
                          const Duration(milliseconds: 300)) {
                    _controller.handleDoubleTap(context, e);
                  }
                  _lastPointerDownTime = now;
                },
                child: EmbeddedScrcpyViewer(deviceId: widget.deviceId),
              ),
            ),
          ),
        ],
      );
    }
    else {
      contentWidget = const Center(child: Text('未连接或投屏已停止'));
    }

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xff121212)
          : const Color(0xfff8f9fa),
      body: DragDropTargetOverlay(
        // 支持将 APK 或普通文件拖拽入投屏窗口进行安装/上传
        onDragDone: (files) => _controller.handleDrop(context, files),
        child: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: (event) {
            // 全屏状态下按 ESC 退出全屏
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              if (_controller.isFullScreen) {
                _controller.toggleFullScreen(context, false);
              }
            }
          },
          child: Column(
            children: [
              // 非全屏状态下渲染窗口自定义拖拽标题栏
              if (!_controller.isFullScreen)
                DragToMoveArea(
                  child: Container(
                    height: 30,
                    padding: EdgeInsets.only(
                      left: Platform.isMacOS ? 80 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: headerBgColor,
                      border: Border(
                        bottom: BorderSide(color: borderColor, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.deviceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontSize: 16),
                          ),
                        ),
                        // 窗口置顶按钮
                        MirrorToolbarButton(
                          icon: Icon(
                            _controller.isAlwaysOnTop
                                ? CupertinoIcons.pin_fill
                                : CupertinoIcons.pin,
                            color: _controller.isAlwaysOnTop
                                ? Colors.orange
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                          tooltip: _controller.isAlwaysOnTop ? '取消置顶' : '置顶窗口',
                          onPressed: _controller.toggleAlwaysOnTop,
                        ),
                        // 窗口全屏按钮
                        MirrorToolbarButton(
                          icon: Icon(
                            _controller.isFullScreen
                                ? CupertinoIcons.fullscreen_exit
                                : CupertinoIcons.fullscreen,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          tooltip: _controller.isFullScreen ? '退出全屏' : '全屏显示',
                          onPressed: () => _controller.toggleFullScreen(
                            context,
                            !_controller.isFullScreen,
                          ),
                        ),
                        // 投屏高级设置按钮
                        MirrorToolbarButton(
                          icon: Icon(
                            CupertinoIcons.settings,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                          tooltip: '投屏画质设置',
                          onPressed: () => showMirrorSettingsDialog(
                            context: context,
                            ref: ref,
                            deviceId: widget.deviceId,
                            windowId: widget.windowId,
                            isAlwaysOnTop: _controller.isAlwaysOnTop,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(child: contentWidget),
            ],
          ),
        ),
      ),
    );
  }
}
