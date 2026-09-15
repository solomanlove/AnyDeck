import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/providers/app_providers.dart';
import 'controller/screenshot_controller.dart';
import 'widgets/screenshot_canvas.dart';
import 'widgets/screenshot_toolbar.dart';

/// 鸿蒙手机专属截图与录屏页面。
///
/// 独立文件承载鸿蒙系统的截屏展示逻辑，复用公共的 ScreenshotToolbar 与 ScreenshotCanvas，
/// 不引入 Android 特有的 uiautomator 布局分析树组件。
class HarmonyScreenshotTab extends ConsumerStatefulWidget {
  /// 创建鸿蒙专属截图页面实例
  const HarmonyScreenshotTab({super.key, required this.device});

  /// 当前目标设备
  final AdbDevice device;

  @override
  ConsumerState<HarmonyScreenshotTab> createState() =>
      _HarmonyScreenshotTabState();
}

class _HarmonyScreenshotTabState extends ConsumerState<HarmonyScreenshotTab> {
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey<ScreenshotCanvasState> _canvasKey =
      GlobalKey<ScreenshotCanvasState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller =
          ref.read(screenshotLayoutControllerProvider(widget.device.id).notifier);
      final state =
          ref.read(screenshotLayoutControllerProvider(widget.device.id));
      if (!state.hasImage && !state.isLoading) {
        controller.captureScreenshot();
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HarmonyScreenshotTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      ref
          .read(screenshotLayoutControllerProvider(oldWidget.device.id).notifier)
          .resetForDeviceSwitch();
      _transformationController.value = Matrix4.identity();

      final controller =
          ref.read(screenshotLayoutControllerProvider(widget.device.id).notifier);
      controller.captureScreenshot();
    }
  }

  double _getDeviceLogicalDensity() {
    final overview =
        ref.watch(cachedDeviceOverviewProvider(widget.device.id)).value;
    if (overview == null) return 1.0;
    final densityStr = overview.logicalDensity;
    final match = RegExp(r'^([0-9.]+)\s*x').firstMatch(densityStr);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 1.0;
    }
    return 1.0;
  }

  @override
  Widget build(BuildContext context) {
    // 监听全局 Tab 切换：切出暂停连续截图，切回恢复
    ref.listen<int>(selectedToolTabProvider, (previous, next) {
      final controller =
          ref.read(screenshotLayoutControllerProvider(widget.device.id).notifier);
      if (previous == 9 && next != 9) {
        controller.pauseAutoRefreshForTabSwitch();
      } else if (previous != 9 && next == 9) {
        controller.resumeAutoRefreshAfterTabSwitch();
      }
    });

    final isOnline = ref.watch(deviceOnlineProvider(widget.device.id));
    if (!isOnline) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.bolt_slash, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('鸿蒙手机离线，无法获取截图和录屏'),
          ],
        ),
      );
    }

    final state =
        ref.watch(screenshotLayoutControllerProvider(widget.device.id));
    final controller =
        ref.read(screenshotLayoutControllerProvider(widget.device.id).notifier);
    final density = _getDeviceLogicalDensity();

    if (state.error != null && !state.hasImage && !state.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 48,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => controller.captureScreenshot(),
                icon: const Icon(CupertinoIcons.refresh),
                label: Text(context.l10n.t('refresh')),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // 顶部复用截图控制工具栏
        ScreenshotToolbar(
          device: widget.device,
          state: state,
          onRefresh: () => controller.captureScreenshot(),
          onSave: () => controller.saveScreenshotOrExport(context),
          onCopy: () => controller.copyScreenshotImage(context),
          onRotateLeft: controller.rotateLeft,
          onRotateRight: controller.rotateRight,
          onZoomIn: () => _canvasKey.currentState?.zoom(1.2),
          onZoomOut: () => _canvasKey.currentState?.zoom(0.8),
          onZoom1To1: () => _canvasKey.currentState?.zoom1to1(),
          onZoomReset: () {
            _transformationController.value = Matrix4.identity();
          },
          onToggleAutoRefresh: controller.toggleAutoRefresh,
          onStartRecording: () => controller.startRecording(context: context),
          onStopRecording: () => controller.stopRecording(context: context),
          onToggleLayoutAnalysis: (_) {},
          onExpandAll: () {},
          onCollapseAll: () {},
          onShowPropertiesChanged: (_) {},
          onShowBordersChanged: (_) {},
          onUseDpChanged: (_) {},
        ),
        // 中央复用截图画布
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ScreenshotCanvas(
                key: _canvasKey,
                decodedImage: state.decodedImage,
                rotationAngle: state.rotation,
                transformationController: _transformationController,
                isLayoutAnalysis: false,
                rootNode: null,
                selectedNode: null,
                hoveredNode: null,
                showBorders: false,
                enableClickSelect: false,
                useDp: false,
                deviceScale: density,
                onNodeSelected: (_) {},
                onNodeHovered: (_) {},
              ),
              if (state.isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.1),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
