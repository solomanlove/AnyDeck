import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_selector/file_selector.dart';

import '../../l10n/app_localizations.dart';
import '../../settings/app_settings_controller.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/transfer_provider.dart';
import '../../../features/dashboard/presentation/widgets/dashboard_snack.dart';
import '../../../core/scrcpy/embedded_scrcpy_service.dart';
import 'mirror_aspect_resolver.dart';
import 'mirror_window_frame_adapter.dart';

/// 投屏独立窗口的业务逻辑与状态控制器。
/// 采用 ChangeNotifier 实现，将功能逻辑与 UI 界面彻底剥离。
class MirrorWindowController extends ChangeNotifier {
  final WidgetRef ref;
  final String deviceId;
  final String windowId;
  final String? newDisplay;
  final String? startApp;

  MirrorWindowController({
    required this.ref,
    required this.deviceId,
    required this.windowId,
    this.newDisplay,
    this.startApp,
  });

  // ==================== 状态属性 (State Properties) ====================

  /// 投屏加载状态
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// 启动投屏失败时的错误消息
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 窗口是否处于全屏状态
  bool _isFullScreen = false;
  bool get isFullScreen => _isFullScreen;

  /// 窗口是否置顶
  bool _isAlwaysOnTop = false;
  bool get isAlwaysOnTop => _isAlwaysOnTop;

  /// 用于获取投屏 Viewer 尺寸的全局 Key
  late final GlobalKey _viewerKey;

  /// 用于 macOS 原生窗口通讯的 MethodChannel
  static const _windowChannel = MethodChannel('adb_manage/window');

  /// 自动缩放的周期定时器
  Timer? _autoFitTimer;

  final MirrorAspectResolver _aspectResolver = MirrorAspectResolver();
  bool _isResolvingAspect = false;
  bool _isRestartingForRotation = false;
  DateTime? _lastStreamRestartAt;
  DateTime? _resumeAspectDetectionAt;

  // ==================== 初始化与销毁 (Init & Dispose) ====================

  /// 初始化控制器，绑定视图 Key 并启动投屏相关逻辑
  void init(GlobalKey viewerKey) {
    _viewerKey = viewerKey;

    // 从全局配置中读取是否默认置顶
    _isAlwaysOnTop = ref.read(appSettingsProvider).scrcpyAlwaysOnTop;

    // 针对 macOS 进行特殊窗口通道事件的绑定
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler((call) async {
        if (call.method == 'onWindowEnterFullScreen') {
          _isFullScreen = true;
          notifyListeners();
        } else if (call.method == 'onWindowLeaveFullScreen') {
          _isFullScreen = false;
          notifyListeners();
        }
      });
      _windowChannel.invokeMethod('initWindow').catchError((e) {
        debugPrint('Failed to initialize subwindow listeners on macOS: $e');
      });
    }

    // 设置初始置顶状态
    _windowChannel.invokeMethod('setAlwaysOnTop', _isAlwaysOnTop).catchError((
      e,
    ) {
      debugPrint('Failed to set always on top in controller init: $e');
    });

    // 异步启动投屏服务
    startMirroring();
  }

  /// 释放控制器持有的资源
  void disposeController() {
    if (Platform.isMacOS) {
      _windowChannel.setMethodCallHandler(null);
    }
    _autoFitTimer?.cancel();
  }

  // ==================== 核心逻辑方法 (Logic Methods) ====================

  /// 开始/重试启动投屏服务
  Future<void> startMirroring() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 检查当前设备是否已经有激活的投屏通道
      final activeMirror = ref.read(activeEmbeddedMirrorProvider(deviceId));
      if (activeMirror == null) {
        // 激活投屏
        await ref
            .read(activeEmbeddedMirrorProvider(deviceId).notifier)
            .toggleMirroring(newDisplay: newDisplay, startApp: startApp);
      }
      _isLoading = false;
      notifyListeners();

      // 启动定时自适应窗口大小
      _scheduleAutoFit();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// 切换窗口全屏状态
  void toggleFullScreen(BuildContext context, bool fullscreen) async {
    _isFullScreen = fullscreen;
    notifyListeners();

    if (Platform.isMacOS) {
      try {
        await _windowChannel.invokeMethod('setFullScreen', fullscreen);
      } catch (e) {
        debugPrint('Failed to set fullscreen on macOS: $e');
      }
    } else {
      try {
        await windowManager.setFullScreen(fullscreen);
      } catch (e) {
        debugPrint('Failed to set fullscreen: $e');
      }
    }

    // 仅在进入全屏时弹出提示信息
    if (fullscreen && context.mounted) {
      DashboardSnack.show(context, '已进入全屏，按 ESC 或双击屏幕可退出全屏');
    }
  }

  /// 外部窗口管理器通知：进入全屏
  void onWindowEnterFullScreen() {
    _isFullScreen = true;
    notifyListeners();
  }

  /// 外部窗口管理器通知：离开全屏
  void onWindowLeaveFullScreen() {
    _isFullScreen = false;
    notifyListeners();
  }

  /// 切换窗口置顶状态
  Future<void> toggleAlwaysOnTop() async {
    final nextState = !_isAlwaysOnTop;
    try {
      await _windowChannel.invokeMethod('setAlwaysOnTop', nextState);
      _isAlwaysOnTop = nextState;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to toggle always on top: $e');
    }
  }

  /// 双击黑边事件处理：退出全屏或自适应窗口尺寸
  void handleDoubleTap(BuildContext context, PointerDownEvent e) async {
    // 获取设备的物理分辨率
    final overviewAsync = ref.read(deviceOverviewProvider(deviceId));
    final resolution = overviewAsync.maybeWhen(
      data: (overview) => overview.physicalResolution,
      orElse: () => null,
    );
    final aspectRatio = await _aspectResolver.resolveNow(
      ref: ref,
      deviceId: deviceId,
      resolution: resolution,
      fallbackAspect: _getAspectRatio,
    );

    if (!context.mounted) return;

    final renderBox =
        _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final viewerSize = renderBox.size;
    final double viewerW = viewerSize.width;
    final double viewerH = viewerSize.height;
    if (viewerW <= 0 || viewerH <= 0) return;

    final localPos = renderBox.globalToLocal(e.position);
    final containerRatio = viewerW / viewerH;

    // 检测双击点是否落在黑边区域
    bool isOnBlackBorder = false;
    if (containerRatio > aspectRatio) {
      // 容器偏宽，左右两侧存在黑边
      final textureW = viewerH * aspectRatio;
      final leftBorder = (viewerW - textureW) / 2;
      final rightBorder = (viewerW + textureW) / 2;
      if (localPos.dx < leftBorder || localPos.dx > rightBorder) {
        isOnBlackBorder = true;
      }
    } else if (containerRatio < aspectRatio) {
      // 容器偏窄，上下两侧存在黑边
      final textureH = viewerW / aspectRatio;
      final topBorder = (viewerH - textureH) / 2;
      final bottomBorder = (viewerH + textureH) / 2;
      if (localPos.dy < topBorder || localPos.dy > bottomBorder) {
        isOnBlackBorder = true;
      }
    }

    if (isOnBlackBorder) {
      if (_isFullScreen) {
        // 如果是全屏，则退出全屏
        toggleFullScreen(context, false);
      } else {
        // 非全屏下双击黑边，自动缩放窗口以贴合设备宽高比
        Future.delayed(const Duration(milliseconds: 50), () {
          MirrorWindowFrameAdapter.fitWindowToAspectRatio(
            windowChannel: _windowChannel,
            aspectRatio: aspectRatio,
            viewerW: viewerW,
            viewerH: viewerH,
          );
        });
      }
    } else {
      debugPrint(
        '[MirrorWindow] Double tap on device screen, ignore fullscreen toggle.',
      );
    }
  }

  /// 处理拖拽文件/APK 的逻辑
  Future<void> handleDrop(BuildContext context, List<XFile> files) async {
    if (files.isEmpty) return;

    final appService = ref.read(appManagementServiceProvider);
    final fileService = ref.read(fileManagerServiceProvider);
    final transferNotifier = ref.read(transferListProvider.notifier);

    for (final file in files) {
      if (!context.mounted) return;
      final isApk = file.path.toLowerCase().endsWith('.apk');
      final taskId = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';

      // 往全局传输列表中添加一个新任务
      transferNotifier.addTask(
        TransferTask(
          id: taskId,
          name: file.name,
          deviceId: deviceId,
          isApk: isApk,
        ),
      );

      if (context.mounted) {
        DashboardSnack.show(
          context,
          isApk
              ? context.l10n.t('installingApk')
              : context.l10n.t('uploadingFile'),
        );
      }

      try {
        // 执行安装或文件推送
        final result = isApk
            ? await appService.installApk(deviceId, file.path)
            : await fileService.push(deviceId, file.path, '/sdcard/Download/');

        // 更新任务结果状态
        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: result.isSuccess,
          error: result.isSuccess ? null : result.message,
        );

        if (!context.mounted) return;

        // 根据结果拼装提示文案
        final message = isApk
            ? (result.isSuccess
                  ? context.l10n
                        .t('apkInstallSuccess')
                        .replaceAll('{name}', file.name)
                  : context.l10n
                        .t('apkInstallFailed')
                        .replaceAll('{name}', file.name)
                        .replaceAll('{error}', result.message))
            : (result.isSuccess
                  ? context.l10n
                        .t('fileUploadSuccess')
                        .replaceAll('{name}', file.name)
                  : context.l10n
                        .t('fileUploadFailed')
                        .replaceAll('{name}', file.name)
                        .replaceAll('{error}', result.message));

        DashboardSnack.show(context, message, isError: !result.isSuccess);
      } catch (e) {
        transferNotifier.updateTask(
          id: taskId,
          isDone: true,
          isSuccess: false,
          error: e.toString(),
        );
        if (context.mounted) {
          DashboardSnack.show(context, '${file.name}: $e', isError: true);
        }
      }
    }
  }

  // ==================== 内部私有方法 (Private Methods) ====================

  /// 解析屏幕宽高比
  double _getAspectRatio(String? resolutionStr) {
    if (resolutionStr == null || resolutionStr == '-') return 9 / 16;
    final match = RegExp(r'(\d+)\s*[xX]\s*(\d+)').firstMatch(resolutionStr);
    if (match != null) {
      final w = int.parse(match.group(1)!);
      final h = int.parse(match.group(2)!);
      if (w > 0 && h > 0) {
        return w / h;
      }
    }
    return 9 / 16;
  }

  /// 周期轮询横竖屏变化，仅重启视频流，不自动改变窗口外框尺寸。
  void _scheduleAutoFit() {
    _autoFitTimer?.cancel();
    _autoFitTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) async {
      if (_isResolvingAspect) return;
      final resumeAt = _resumeAspectDetectionAt;
      if (resumeAt != null && DateTime.now().isBefore(resumeAt)) return;
      _isResolvingAspect = true;
      try {
        final overviewAsync = ref.read(deviceOverviewProvider(deviceId));
        final resolution = overviewAsync.maybeWhen(
          data: (overview) => overview.physicalResolution,
          orElse: () => null,
        );
        final aspectResult = await _aspectResolver.resolveForAutoFit(
          ref: ref,
          deviceId: deviceId,
          resolution: resolution,
          fallbackAspect: _getAspectRatio,
        );
        if (aspectResult.shouldRestartStream) {
          unawaited(_restartForStreamMismatch());
        }
      } finally {
        _isResolvingAspect = false;
      }
    });
  }

  Future<void> _restartForStreamMismatch() async {
    if (_isRestartingForRotation) return;
    final now = DateTime.now();
    final lastRestartAt = _lastStreamRestartAt;
    if (lastRestartAt != null &&
        now.difference(lastRestartAt) < const Duration(milliseconds: 800)) {
      return;
    }
    _isRestartingForRotation = true;
    _lastStreamRestartAt = now;
    try {
      await ref
          .read(activeEmbeddedMirrorProvider(deviceId).notifier)
          .restartMirroring(newDisplay: newDisplay, startApp: startApp);
      _aspectResolver.resetAfterStreamRestart();
      _resumeAspectDetectionAt = DateTime.now().add(
        const Duration(milliseconds: 1200),
      );
    } catch (e) {
      debugPrint('Failed to restart mirroring after rotation change: $e');
    } finally {
      _isRestartingForRotation = false;
    }
  }
}
