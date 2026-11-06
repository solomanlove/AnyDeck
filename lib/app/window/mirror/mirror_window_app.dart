import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../shortcuts/mirror_shortcut_scope.dart';
import '../../theme/app_theme.dart';
import '../window_close_shortcut.dart';
import '../../../features/control/embedded_scrcpy_viewer.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import '../../../core/scrcpy/app_mirror_task_monitor.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/apps/adb_package.dart';
import '../../widget/app_toast.dart';
import '../../../features/widgets/drag_drop_target_overlay.dart';
import 'mirror_floating_toolbar.dart';
import 'mirror_immersive_overlay.dart';
import 'mirror_device_info_overlay.dart';
import 'mirror_session_status_bar.dart';
import 'mirror_settings_dialog.dart';
import 'mirror_window_controller.dart';
import 'widget/mirror_app_quick_actions_dialog.dart';
import 'widget/mirror_status_view.dart';
import 'widget/fusion_resize_transition.dart';
import 'widget/fusion_app_on_phone_placeholder.dart';
import 'widget/mirror_foreground_app_button.dart';
import 'widget/mirror_window_title_bar.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/harmony/harmony_mirror_service.dart';
import '../desktop_window_title_service.dart';
import '../sub_window_method_dispatcher.dart';
import 'ios_airplay_mirror_content.dart';
import 'android_mirror_transport_host.dart';
import '../../../core/scrcpy/mirror_transport_type.dart';
import '../../../core/scrcpy/fusion_mode_preference.dart';
import '../../../features/control/whiteboard/mirror_whiteboard_controller.dart';

part 'mirror_window_view.dart';
part 'mirror_window_title_bar.dart';

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
        autofocus: false,
        child: MirrorShortcutScope(
          child: isIos || isHarmony
              ? Builder(builder: (context) => buildContent(context, deviceId))
              : AndroidMirrorTransportHost(
                  deviceId: deviceId,
                  builder: buildContent,
                ),
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

  /// 仅融合应用窗口监测目标 Task 所在的 Android display。
  AppMirrorTaskMonitor? _appTaskMonitor;

  /// 用于捕获键盘事件的 FocusNode
  late final FocusNode _keyboardFocusNode;

  /// 仅当前投屏窗口使用的本地白板；无需跨 Isolate 同步。
  final MirrorWhiteboardController _whiteboard = MirrorWhiteboardController();
  bool _whiteboardMode = false;

  /// 记录上一次鼠标按下的时间，用于辅助判定双击事件
  DateTime? _lastPointerDownTime;

  /// 用于获取投屏窗口实际渲染尺寸的 Key
  final GlobalKey _viewerKey = GlobalKey();

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
    if (widget.startApp != null && !widget.isIos && !widget.isHarmony) {
      _appTaskMonitor = AppMirrorTaskMonitor(
        adbService: ref.read(adbServiceProvider),
        deviceId: widget.deviceId,
        packageName: widget.startApp!,
        virtualDisplayId: () => ref
            .read(embeddedScrcpyServiceProvider)
            .getVirtualDisplayId(widget.deviceId),
        isReady: () => !_controller.isLoading &&
            _controller.errorMessage == null,
      )..start();
    }

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
    _appTaskMonitor?.dispose();
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
      if (_controller.isLoading || _controller.errorMessage != null) {
        _appTaskMonitor?.suspend();
      }
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

  /// 用户点击占位页后将目标 App 放回当前虚拟副屏。
  Future<void> _restartFusionApp() async {
    try {
      await _appTaskMonitor?.restartOnVirtualDisplay();
    } catch (error) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.t('fusionRestartFailed')
              .replaceAll('{error}', error.toString()),
          isError: true,
        );
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

  void _refreshView(VoidCallback callback) => setState(callback);

  @override
  Widget build(BuildContext context) => _buildWindow(context);
}
