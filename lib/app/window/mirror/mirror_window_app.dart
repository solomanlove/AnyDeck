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
import '../../../core/providers/app_providers.dart';
import '../../../core/apps/adb_package.dart';
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

  /// 前台应用图标悬浮状态，用于悬浮动画与高亮样式
  bool _isIconHovered = false;

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

    // 监听窗口状态变化，用于同步全屏状态和比例锁定
    windowManager.addListener(this);

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

    windowManager.removeListener(this);
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  /// 监听控制器属性变动时的回调
  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
      // 如果进入了全屏，确保键盘焦点不丢失，主动在后帧请求根焦点，使得 ESC 监听有效
      if (_controller.isFullScreen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controller.isFullScreen) {
            _keyboardFocusNode.requestFocus();
          }
        });
      }
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

  @override
  void onWindowMaximize() {
    _controller.onWindowMaximize();
  }

  @override
  void onWindowUnmaximize() {
    _controller.onWindowUnmaximize();
  }

  @override
  void onWindowResized() {
    _controller.onWindowResized();
  }

  // ==================== 界面渲染 (UI Build) ====================

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final overviewAsync = ref.watch(deviceOverviewProvider(widget.deviceId));
    final sdkVersion = overviewAsync.maybeWhen(
      data: (overview) {
        final match = RegExp(r'API\s+(\d+)').firstMatch(overview.androidVersion);
        return match != null ? (int.tryParse(match.group(1) ?? '') ?? 0) : 0;
      },
      orElse: () => 0,
    );
    final isAudioForwarded = (sdkVersion >= 30) && settings.mirrorAudioEnabled;

    // 监听设备在线状态，若设备断开则强制停止投屏
    ref.listen<bool>(deviceOnlineProvider(widget.deviceId), (previous, next) {
      if (!next) {
        _controller.forceStopMirroring();
      }
    });

    // 监听包列表加载状态，以同步最新的前台应用信息
    ref.listen<AsyncValue<List<AdbPackage>>>(
      packagesProvider(widget.deviceId),
      (previous, next) {
        if (next is AsyncData<List<AdbPackage>>) {
          _controller.updateForegroundPackageFromList(next.value);
        }
      },
    );


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
    //加载中
    if (_controller.isLoading) {
      contentWidget = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('startingMirrorService'),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      );
    }
    //加载出错了
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
                context.l10n.t('mirrorStartFailed'),
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
                onPressed: _controller.restartMirroring,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.t('retry')),
              ),
            ],
          ),
        ),
      );
    }
    //投屏正常
    else if (isMirrorActive) {
      contentWidget = Column(
        children: [
          // 非全屏状态下展示顶部浮动操作栏
          if (!_controller.isFullScreen)
            SizedBox(
              width: double.infinity,
              child: MirrorFloatingToolbar(
                deviceId: widget.deviceId,
                windowId: widget.windowId,
                controller: _controller,
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
                  // 只有开启了自动识别设置，点击手机画面时才触发自动防抖识别
                  if (settings.autoIdentifyForegroundApp) {
                    _controller.triggerIdentifyForegroundApp();
                  }
                },
                child: EmbeddedScrcpyViewer(
                  deviceId: widget.deviceId,
                  isFullScreen: _controller.isFullScreen,
                  onEscapePressed: () {
                    if (_controller.isFullScreen) {
                      _controller.toggleFullScreen(context, false);
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      );
    }
    //停止投屏或者设备断开
    else {
      contentWidget = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l10n.t('mirrorStopped'),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _controller.restartMirroring,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.t('retry')),
            ),
          ],
        ),
      );
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
                    padding: EdgeInsets.only(left: Platform.isMacOS ? 80 : 16),
                    decoration: BoxDecoration(
                      color: headerBgColor,
                      border: Border(
                        bottom: BorderSide(color: borderColor, width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: widget.deviceName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(fontSize: 16),
                                      ),
                                      if (isAudioForwarded)
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.top,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Tooltip(
                                              message: context.l10n.t('audioForwardingTooltip'),
                                              child: Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.startApp == null && _controller.currentForegroundPackage != null) ...[
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: context.l10n.t('appMirroring'),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    onEnter: (_) => setState(() => _isIconHovered = true),
                                    onExit: (_) => setState(() => _isIconHovered = false),
                                    child: AnimatedScale(
                                      scale: _isIconHovered ? 1.2 : 1.0,
                                      duration: const Duration(milliseconds: 100),
                                      child: GestureDetector(
                                        onTap: () => _controller.openAppMirrorWindow(context),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: _isIconHovered
                                                  ? Colors.orange.withValues(alpha: 0.8)
                                                  : Colors.transparent,
                                              width: 1,
                                            ),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: (_controller.currentForegroundPackage!.iconLocalPath != null &&
                                                    File(_controller.currentForegroundPackage!.iconLocalPath!).existsSync())
                                                ? Image.file(
                                                    File(
                                                      _controller
                                                          .currentForegroundPackage!
                                                          .iconLocalPath!,
                                                    ),
                                                    width: 18,
                                                    height: 18,
                                                    fit: BoxFit.contain,
                                                    errorBuilder:
                                                        (context, error, stackTrace) =>
                                                            Icon(
                                                              CupertinoIcons.app,
                                                              size: 16,
                                                              color: isDark ? Colors.white70 : Colors.black87,
                                                             ),
                                                   )
                                                : Icon(
                                                    CupertinoIcons.app,
                                                    size: 16,
                                                    color: isDark ? Colors.white70 : Colors.black87,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // 重新连接/刷新按钮
                        MirrorToolbarButton(
                          icon: Icon(
                            CupertinoIcons.refresh,
                            color: isDark ? Colors.white70 : Colors.black87,
                            size: 16,
                          ),
                          tooltip: context.l10n.t('retry'),
                          onPressed: _controller.restartMirroring,
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
                          tooltip: _controller.isAlwaysOnTop
                              ? context.l10n.t('unpinAlwaysOnTop')
                              : context.l10n.t('pinAlwaysOnTop'),
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
                          tooltip: _controller.isFullScreen
                              ? context.l10n.t('exitFullScreen')
                              : context.l10n.t('enterFullScreen'),
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
                          tooltip: context.l10n.t('mirrorQualitySettings'),
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
