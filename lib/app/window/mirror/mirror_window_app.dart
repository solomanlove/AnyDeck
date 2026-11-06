import 'dart:async';
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
import '../window_close_shortcut.dart';
import '../../../features/control/embedded_scrcpy_viewer.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/apps/adb_package.dart';
import '../../../features/widgets/drag_drop_target_overlay.dart';
import 'mirror_floating_toolbar.dart';
import 'mirror_immersive_overlay.dart';
import 'mirror_device_info_overlay.dart';
import 'mirror_session_status_bar.dart';
import 'mirror_settings_dialog.dart';
import 'mirror_window_controller.dart';
import 'widget/mirror_app_quick_actions_dialog.dart';
import 'widget/mirror_status_view.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/harmony/harmony_mirror_service.dart';
import '../desktop_window_title_service.dart';
import '../sub_window_method_dispatcher.dart';
import 'ios_airplay_mirror_content.dart';
import 'android_mirror_transport_host.dart';
import '../../../core/scrcpy/mirror_transport_type.dart';
import '../../../core/scrcpy/fusion_mode_preference.dart';
import '../../../features/control/whiteboard/mirror_whiteboard_controller.dart';

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
    final isIos = argument['isIos'] as bool? ?? false;
    final isHarmony = argument['isHarmony'] as bool? ?? false;

    Widget buildContent(BuildContext context, String route) => MirrorWindowContent(
          deviceId: route,
          deviceName: deviceName,
          windowId: windowId,
          newDisplay: newDisplay,
          startApp: startApp,
          physicalDeviceKey: argument['physicalDeviceKey'] as String?,
          initialAlwaysOnTop: argument['alwaysOnTop'] as bool?,
          isIos: isIos,
          isHarmony: isHarmony,
          initialAirplayHandle: argument['airplayHandle'] as int?,
          initialAirplayAspectRatio:
              (argument['airplayAspectRatio'] as num?)?.toDouble(),
        );

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
      home: WindowCloseShortcut(
        child: isIos || isHarmony
            ? Builder(builder: (context) => buildContent(context, deviceId))
            : AndroidMirrorTransportHost(
                deviceId: deviceId,
                builder: buildContent,
              ),
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
    this.physicalDeviceKey,
    this.initialAlwaysOnTop,
    this.isIos = false,
    this.isHarmony = false,
    this.initialAirplayHandle,
    this.initialAirplayAspectRatio,
  });

  final String deviceId;
  final String deviceName;
  final String windowId;
  final String? newDisplay;
  final String? startApp;
  final String? physicalDeviceKey;
  final bool? initialAlwaysOnTop;
  final bool isIos;
  final bool isHarmony;
  final int? initialAirplayHandle;
  final double? initialAirplayAspectRatio;

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

  /// 仅当前投屏窗口使用的本地白板；无需跨 Isolate 同步。
  final MirrorWhiteboardController _whiteboard = MirrorWhiteboardController();
  bool _whiteboardMode = false;

  /// 记录上一次鼠标按下的时间，用于辅助判定双击事件
  DateTime? _lastPointerDownTime;

  /// 用于获取投屏窗口实际渲染尺寸的 Key
  final GlobalKey _viewerKey = GlobalKey();

  /// 前台应用图标悬浮状态，用于悬浮动画与高亮样式
  bool _isIconHovered = false;

  /// 设备标题悬浮状态，仅在进入/离开标题时更新，避免鼠标移动触发高频 rebuild。
  bool _isTitleHovered = false;

  int? _airplayHandle;
  double _airplayAspectRatio = 9.0 / 19.5;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode(debugLabel: 'MirrorWindowKeyboard');
    _whiteboard.addListener(_onWhiteboardChanged);
    _airplayHandle = widget.initialAirplayHandle;
    _airplayAspectRatio = widget.initialAirplayAspectRatio ?? _airplayAspectRatio;

    // 实例化业务逻辑控制器
    _controller = MirrorWindowController(
      ref: ref,
      deviceId: widget.deviceId,
      windowId: widget.windowId,
      newDisplay: widget.newDisplay,
      startApp: widget.startApp,
      physicalDeviceKey: widget.physicalDeviceKey,
      isIos: widget.isIos,
      isHarmony: widget.isHarmony,
    );

    // 监听控制器状态变化，更新 UI
    _controller.addListener(_onControllerChanged);

    // 监听窗口状态变化，用于同步全屏状态和比例锁定
    windowManager.addListener(this);
    SubWindowMethodDispatcher.registerHandler(_handleWindowMethod);

    // 初始化控制器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.init(
        _viewerKey,
        initialAlwaysOnTop: widget.initialAlwaysOnTop,
        autoStartMirroring: _airplayHandle == null,
      );
      // 初始化读取了默认置顶设置，同步 AirPlay 标题栏的首次图标状态。
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // 移除监听并释放控制器资源
    _controller.removeListener(_onControllerChanged);
    _controller.disposeController();

    windowManager.removeListener(this);
    SubWindowMethodDispatcher.removeHandler(_handleWindowMethod);
    _keyboardFocusNode.dispose();
    _whiteboard.removeListener(_onWhiteboardChanged);
    _whiteboard.dispose();
    super.dispose();
  }

  /// AirPlay 建立后切换当前 iOS 投屏窗口的视频源，不创建第二个窗口。
  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    if (call.method == 'closeMirrorWindow') {
      await _controller.forceStopMirroring();
      await windowManager.close();
      return true;
    }
    if (call.method == 'fusionModeChanged') {
      ref.invalidate(deviceFusionModeProvider(widget.deviceId));
      return true;
    }
    if (call.method == 'mirrorSessionStatus') {
      final displayId = ref.read(embeddedScrcpyServiceProvider)
          .getVirtualDisplayId(widget.deviceId);
      final size = ref.read(embeddedScrcpyServiceProvider)
          .getVideoSize(widget.deviceId);
      return {
        'ready': !_controller.isLoading &&
            _controller.errorMessage == null &&
            size != null,
        'displayId': displayId,
        if (_controller.errorMessage != null)
          'error': _controller.errorMessage,
      };
    }
    if (call.method != 'switchIosMirrorSource') return null;
    final arguments = call.arguments;
    if (arguments is! Map) return false;
    final handle = arguments['airplayHandle'];
    if (handle is! int || handle <= 0 || !mounted) return false;
    final ratio = (arguments['airplayAspectRatio'] as num?)?.toDouble();
    _whiteboard.clear();
    setState(() {
      _airplayHandle = handle;
      if (ratio != null && ratio > 0) _airplayAspectRatio = ratio;
    });
    await DesktopWindowTitleService.setTitle(
      '${widget.deviceName} · ${context.l10n.t('iosMirrorWifiAirPlay')}',
    );
    await windowManager.show();
    await windowManager.focus();
    return true;
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

  void _onWhiteboardChanged() {
    if (!mounted || _whiteboardMode == _whiteboard.active) return;
    setState(() => _whiteboardMode = _whiteboard.active);
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
    if (_airplayHandle != null) return;
    _controller.onWindowResized();
  }

  // ==================== 界面渲染 (UI Build) ====================

  /// 前台应用图标按设备当前模式展示入口名称。
  String _appMirrorTooltip(BuildContext context) {
    final mode = ref.watch(deviceFusionModeProvider(widget.deviceId))
        .asData?.value.state;
    final title = context.l10n.t(
      mode == FusionModeState.enabled ? 'fusionAppTooltip' : 'primaryAppTooltip',
    );
    return '$title · ${context.l10n.t('fusionQuickActionsHint')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final airplayHandle = _airplayHandle;
    if (airplayHandle != null) {
      return IosAirPlayMirrorContent(
        handle: airplayHandle,
        deviceName: widget.deviceName,
        initialAspectRatio: _airplayAspectRatio,
        autoHideControls:
            !settings.mirrorControlsAlwaysVisible && !_whiteboardMode,
        isAlwaysOnTop: _controller.isAlwaysOnTop,
        onToggleAlwaysOnTop: _controller.toggleAlwaysOnTop,
        isFullScreen: _controller.isFullScreen,
        onToggleFullScreen: () => _controller.toggleFullScreen(
          context,
          !_controller.isFullScreen,
        ),
        toolbar: MirrorFloatingToolbar(
          deviceId: widget.deviceId,
          deviceName: widget.deviceName,
          windowId: widget.windowId,
          controller: _controller,
          isAirplay: true,
          airplayHandle: airplayHandle,
          whiteboard: _whiteboard,
        ),
        whiteboard: _whiteboard,
        onDisconnected: () {
          if (!mounted ||
              ref.read(activeIosMirrorProvider(widget.deviceId)) == null) {
            return;
          }
          _whiteboard.clear();
          setState(() => _airplayHandle = null);
          unawaited(
            DesktopWindowTitleService.setTitle(
              '${widget.deviceName} · ${context.l10n.t('iosMirrorUsbNative')}',
            ),
          );
        },
      );
    }
    final sdkVersion = ref.watch(deviceSdkVersionProvider(widget.deviceId)) ?? 0;
    final isAudioForwarded =
        (sdkVersion >= 30) &&
        !_controller.isAudioMuted &&
        settings.mirrorAudioEnabled;

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

    // 监听全局设置中投屏窗口置顶的变化
    ref.listen<bool>(
      appSettingsProvider.select((s) => s.scrcpyAlwaysOnTop),
      (previous, next) {
        _controller.updateAlwaysOnTop(next);
      },
    );


    final isIos = widget.isIos ||
        (widget.deviceId.length == 40 && !widget.deviceId.contains(RegExp(r'[^a-fA-F0-9]'))) ||
        (widget.deviceId.length == 25 && widget.deviceId.indexOf('-') == 8);
    final isMirrorActive = isIos
        ? ref.watch(activeIosMirrorProvider(widget.deviceId)) != null
        : (widget.isHarmony
            ? ref.watch(activeHarmonyMirrorProvider(widget.deviceId)) != null
            : ref.watch(activeEmbeddedMirrorProvider(widget.deviceId)) != null);
    final isLiveMirrorVisible = isMirrorActive &&
        !_controller.isLoading &&
        _controller.errorMessage == null;
    final windowBackground = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xff121212)
        : const Color(0xfff8f9fa);
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
      contentWidget = MirrorStatusView(
        rawErrorMessage: _controller.errorMessage,
        onRetry: () {
          _whiteboard.clear();
          _controller.restartMirroring();
        },
        onPrimaryMirror: widget.startApp == null
            ? null
            : () => _controller.openPrimaryMirrorWindow(context),
      );
    }
    //投屏正常
    else if (isMirrorActive) {
      contentWidget = ClipRRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Listener(
                    key: _viewerKey,
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) {
                      if (_whiteboard.active) return;
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
                      whiteboard: _whiteboard,
                      isHarmony: widget.isHarmony,
                      isFullScreen: _controller.isFullScreen,
                      onVideoSizeChanged: (width, height) {
                        _whiteboard.updateVideoOrientation(width, height);
                        _controller.onVideoSizeChanged(width, height);
                      },
                      onIosVideoGeometryChanged: (width, height, viewport) {
                        _whiteboard.updateVideoOrientation(width, height);
                        _controller.onIosVideoGeometryChanged(
                          width, height, viewport);
                      },
                      onEscapePressed: () {
                        if (_controller.isFullScreen) {
                          _controller.toggleFullScreen(context, false);
                        }
                      },
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IgnorePointer(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 160),
                          child: _isTitleHovered && !_controller.isFullScreen
                              ? MirrorDeviceInfoOverlay(
                                  deviceId: widget.deviceId,
                                  deviceName: widget.deviceName,
                                  transport: isIos || widget.isHarmony
                                      ? null
                                      : MirrorTransportType.fromDeviceId(
                                          widget.deviceId,
                                        ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      );
    }
    //停止投屏或者设备断开
    else {
      contentWidget = MirrorStatusView(
        isStoppedState: true,
        onRetry: _controller.restartMirroring,
      );
    }

    return Scaffold(
      backgroundColor: isLiveMirrorVisible
          ? Colors.transparent
          : windowBackground,
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
          child: MirrorImmersiveOverlay(
            autoHide:
                isLiveMirrorVisible &&
                !settings.mirrorControlsAlwaysVisible &&
                !_whiteboardMode,
            viewer: contentWidget,
            titleBar: DragToMoveArea(
                  child: Container(
                    height: 30,
                    padding: EdgeInsets.only(
                      left: Platform.isMacOS ? 80 : 16,
                      right: 4,
                    ),
                    decoration: BoxDecoration(
                      color: windowBackground,
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: MouseRegion(
                                  onEnter: (_) => setState(() => _isTitleHovered = true),
                                  onExit: (_) => setState(() => _isTitleHovered = false),
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: isIos
                                              ? '${widget.deviceName} · ${context.l10n.t('iosMirrorUsbNative')}'
                                              : widget.deviceName,
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
                              ),
                              if (widget.startApp == null && _controller.currentForegroundPackage != null) ...[
                                const SizedBox(width: 8),
                                Tooltip(
                                  message: _appMirrorTooltip(context),
                                  child: MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    onEnter: (_) => setState(() => _isIconHovered = true),
                                    onExit: (_) => setState(() => _isIconHovered = false),
                                    child: AnimatedScale(
                                      scale: _isIconHovered ? 1.2 : 1.0,
                                      duration: const Duration(milliseconds: 100),
                                      child: GestureDetector(
                                        onTap: () => _controller.openAppMirrorWindow(context),
                                        onLongPress: () {
                                          if (_controller.currentForegroundPackage != null) {
                                            showMirrorAppQuickActionsDialog(
                                              context: context,
                                              ref: ref,
                                              deviceId: widget.deviceId,
                                              package: _controller.currentForegroundPackage!,
                                            );
                                          }
                                        },
                                        onSecondaryTap: () {
                                          if (_controller.currentForegroundPackage != null) {
                                            showMirrorAppQuickActionsDialog(
                                              context: context,
                                              ref: ref,
                                              deviceId: widget.deviceId,
                                              package: _controller.currentForegroundPackage!,
                                            );
                                          }
                                        },
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
                                                              color: Theme.of(context).appColors.toolbarForeground,
                                                             ),
                                                   )
                                                : Icon(
                                                    CupertinoIcons.app,
                                                    size: 16,
                                                    color: Theme.of(context).appColors.toolbarForeground,
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
                        if (isMirrorActive)
                          const MirrorSessionDuration(),
                        // 重新连接/刷新按钮
                        MirrorToolbarButton(
                          icon: Icon(
                            CupertinoIcons.refresh,
                            color: Theme.of(context).appColors.toolbarForeground,
                            size: 16,
                          ),
                          tooltip: context.l10n.t('retry'),
                          onPressed: () {
                            _whiteboard.clear();
                            _controller.restartMirroring();
                          },
                        ),
                        // 窗口置顶按钮
                        MirrorToolbarButton(
                          icon: Icon(
                            _controller.isAlwaysOnTop
                                ? CupertinoIcons.pin_fill
                                : CupertinoIcons.pin,
                            color: _controller.isAlwaysOnTop
                                ? Colors.orange
                                : (Theme.of(context).appColors.toolbarForeground),
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
                            color: Theme.of(context).appColors.toolbarForeground,
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
                        if (!isIos)
                          MirrorToolbarButton(
                            icon: Icon(
                              CupertinoIcons.settings,
                              color: Theme.of(context).appColors.toolbarForeground,
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
            toolbar: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Expanded(
                    child: MirrorFloatingToolbar(
                      deviceId: widget.deviceId,
                      deviceName: widget.deviceName,
                      windowId: widget.windowId,
                      controller: _controller,
                      whiteboard: _whiteboard,
                    ),
                  ),
                  MirrorSessionFps(
                    deviceId: widget.deviceId,
                    isIos: isIos,
                    isHarmony: widget.isHarmony,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
