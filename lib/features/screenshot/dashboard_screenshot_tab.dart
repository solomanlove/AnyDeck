import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_localizations.dart';
import '../../core/adb/adb_device.dart';
import '../../core/providers/app_providers.dart';
import '../layout/layout_hierarchy_tree.dart';
import '../layout/layout_properties_table.dart';
import 'controller/screenshot_controller.dart';
import 'widgets/screenshot_canvas.dart';
import 'widgets/screenshot_toolbar.dart';

/// 截图录屏与布局分析主页面容器。
/// 统一管理顶部工具栏、中央共享画布、左侧组件树与右侧属性面板的展开与折叠。
class DashboardScreenshotTab extends ConsumerStatefulWidget {
  const DashboardScreenshotTab({super.key, required this.device});

  final AdbDevice device;

  @override
  ConsumerState<DashboardScreenshotTab> createState() =>
      _DashboardScreenshotTabState();
}

class _DashboardScreenshotTabState
    extends ConsumerState<DashboardScreenshotTab> {
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
        if (state.isLayoutAnalysis) {
          controller.loadLayoutAndScreenshot();
        } else {
          controller.captureScreenshot();
        }
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DashboardScreenshotTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.device.id != widget.device.id) {
      // 切换设备：重置旧设备状态（使进行中的请求失效、关闭布局分析模式）
      ref
          .read(screenshotLayoutControllerProvider(oldWidget.device.id).notifier)
          .resetForDeviceSwitch();
      _transformationController.value = Matrix4.identity();

      // 新设备拉取截图
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
            Text('手机离线，无法获取截图和录屏'),
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
                onPressed: () {
                  if (state.isLayoutAnalysis) {
                    controller.loadLayoutAndScreenshot();
                  } else {
                    controller.captureScreenshot();
                  }
                },
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
        // 1. 顶部公共控制工具栏
        ScreenshotToolbar(
          device: widget.device,
          state: state,
          onRefresh: () {
            if (state.isLayoutAnalysis) {
              controller.loadLayoutAndScreenshot();
            } else {
              controller.captureScreenshot();
            }
          },
          onSave: () => controller.saveScreenshotOrExport(context),
          onCopy: () {
            if (state.isLayoutAnalysis) {
              controller.copySelectedXml(context);
            } else {
              controller.copyScreenshotImage(context);
            }
          },
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
          onToggleLayoutAnalysis: controller.toggleLayoutAnalysis,
          onExpandAll: controller.expandAllNodes,
          onCollapseAll: controller.collapseAllNodes,
          onShowPropertiesChanged: (val) =>
              controller.setShowProperties(val ?? true),
          onShowBordersChanged: (val) =>
              controller.setShowBorders(val ?? false),
          onUseDpChanged: (val) => controller.setUseDp(val ?? true),
        ),
        // 2. 主工作区：普通截图模式单画布，布局分析模式三栏展开
        Expanded(
          child: state.isLayoutAnalysis
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧控件树面板
                    Expanded(
                      flex: state.showProperties ? 3 : 5,
                      child: state.rootNode == null
                          ? _buildHierarchyPlaceholder(context)
                          : LayoutHierarchyTree(
                              rootNode: state.rootNode!,
                              loading: state.isLoading,
                              selectedNode: state.selectedNode,
                              hoveredNode: state.hoveredNode,
                              expandedNodes: state.expandedNodes,
                              onNodeSelected: controller.selectNode,
                              onNodeHovered: controller.hoverNode,
                              onNodeExpansionChanged:
                                  controller.toggleNodeExpanded,
                            ),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.3),
                    ),
                    // 中间共享截图画布
                    Expanded(
                      flex: state.showProperties ? 4 : 5,
                      child: ScreenshotCanvas(
                        key: _canvasKey,
                        decodedImage: state.decodedImage,
                        rotationAngle: state.rotation,
                        transformationController: _transformationController,
                        isLayoutAnalysis: true,
                        rootNode: state.rootNode,
                        selectedNode: state.selectedNode,
                        hoveredNode: state.hoveredNode,
                        showBorders: state.showBorders,
                        enableClickSelect: state.enableClickSelect,
                        useDp: state.useDp,
                        deviceScale: density,
                        isLoading: state.isLoading,
                        onNodeSelected: controller.selectNode,
                        onNodeHovered: controller.hoverNode,
                      ),
                    ),
                    // 右侧属性面板
                    if (state.showProperties) ...[
                      VerticalDivider(
                        width: 1,
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.3),
                      ),
                      Expanded(
                        flex: 3,
                        child: LayoutPropertiesTable(
                          selectedNode: state.selectedNode,
                          useDp: state.useDp,
                          deviceScale: density,
                        ),
                      ),
                    ],
                  ],
                )
              : ScreenshotCanvas(
                  key: _canvasKey,
                  decodedImage: state.decodedImage,
                  rotationAngle: state.rotation,
                  transformationController: _transformationController,
                  isLayoutAnalysis: false,
                  isLoading: state.isLoading,
                ),
        ),
      ],
    );
  }

  Widget _buildHierarchyPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? Colors.white.withValues(alpha: 0.02)
        : Colors.white.withValues(alpha: 0.2);
    final headerColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.02);
    final labelColor = isDark ? Colors.grey[300] : Colors.blueGrey;

    return Container(
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerColor,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.square_stack_3d_up,
                  size: 18,
                  color: labelColor,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.t('nodeHierarchy'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: labelColor,
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
