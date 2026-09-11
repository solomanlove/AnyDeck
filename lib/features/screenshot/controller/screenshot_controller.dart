import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings/app_settings_controller.dart';
import '../../../core/ios/ios_mirror_service.dart';
import '../../../core/layout_inspector/layout_inspector_service.dart';
import '../../../core/layout_inspector/layout_node.dart';
import '../../../core/providers/app_providers.dart';
import '../model/screenshot_state.dart';
import 'screenshot_export_helper.dart';
import 'screenshot_record_runner.dart';

/// 设备会话级截图与布局分析统一状态控制器。
class ScreenshotController extends Notifier<ScreenshotLayoutState> {
  ScreenshotController(this.deviceId);

  final String deviceId;

  int _requestId = 0;
  Timer? _autoRefreshTimer;
  ScreenshotRecordRunner? _recordRunner;
  ui.Image? _currentDecodedImage;

  @override
  ScreenshotLayoutState build() {
    _recordRunner = ScreenshotRecordRunner(
      deviceId: deviceId,
      ref: ref,
      onPhaseChanged: (phase) {
        state = state.copyWith(recordPhase: phase);
      },
      onDurationChanged: (duration) {
        state = state.copyWith(recordDuration: duration);
      },
    );

    ref.onDispose(() {
      _autoRefreshTimer?.cancel();
      _recordRunner?.dispose();
      _currentDecodedImage?.dispose();
      _currentDecodedImage = null;
    });

    return const ScreenshotLayoutState();
  }

  /// 递归展开节点及其子节点
  void _expandAll(LayoutNode node, Set<LayoutNode> result) {
    result.add(node);
    for (final child in node.children) {
      _expandAll(child, result);
    }
  }

  /// 获取目标设备的真实对象
  RegisteredDevice? _getDevice() {
    final list = ref.read(deviceRegistryProvider);
    try {
      return list.firstWhere((d) => d.id == deviceId);
    } catch (_) {
      return null;
    }
  }

  /// 普通截图拉取（支持单次或连续后台截图）
  Future<void> captureScreenshot({bool isAuto = false}) async {
    if (state.isLoading && !isAuto) return;
    final currentRequestId = ++_requestId;

    state = state.copyWith(
      isLoading: !isAuto,
      clearError: true,
    );

    try {
      final device = _getDevice();
      final bytes = device?.isIos == true
          ? await ref.read(iosCommandServiceProvider).captureScreenshot(deviceId)
          : device?.isHarmony == true
          ? await ref.read(hdcServiceProvider).captureScreenshot(deviceId)
          : await ref.read(adbServiceProvider).captureScreenshot(deviceId);

      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final decodedImg = frameInfo.image;
      codec.dispose();

      if (currentRequestId != _requestId || !ref.mounted) {
        decodedImg.dispose();
        return;
      }

      final oldImg = _currentDecodedImage;
      _currentDecodedImage = decodedImg;
      state = state.copyWith(
        rawScreenshotBytes: bytes,
        decodedImage: decodedImg,
        imgWidth: decodedImg.width,
        imgHeight: decodedImg.height,
        isLoading: false,
        clearError: true,
      );
      oldImg?.dispose();
    } catch (e) {
      if (currentRequestId == _requestId && ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          error: e.toString(),
        );
        if (isAuto) {
          _autoRefreshTimer?.cancel();
          state = state.copyWith(isAutoRefresh: false);
        }
      }
    }
  }

  /// 布局分析模式下的原子化刷新：并发获取截图与 XML 布局。
  /// 当且仅当两者全部获取成功时，整体替换画面与节点树；失败保留上一份完整数据并记录错误。
  Future<void> loadLayoutAndScreenshot({bool clearContent = false}) async {
    final currentRequestId = ++_requestId;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearSelectedNode: clearContent,
      clearHoveredNode: clearContent,
      rootNode: clearContent ? null : state.rootNode,
      xmlContent: clearContent ? null : state.xmlContent,
    );

    try {
      final service = ref.read(layoutInspectorServiceProvider);

      // 并发执行截图与布局转储
      final screenshotFuture = service.captureScreenshot(deviceId);
      final layoutFuture = service.captureLayout(deviceId);

      final screenshotBytes = await screenshotFuture;
      final (parsedRoot, xmlContent) = await layoutFuture;

      final codec = await ui.instantiateImageCodec(screenshotBytes);
      final frameInfo = await codec.getNextFrame();
      final decodedImg = frameInfo.image;
      codec.dispose();

      // 请求失效检查（加载期间若被关闭、已销毁或触发了新请求则丢弃）
      if (currentRequestId != _requestId || !ref.mounted) {
        decodedImg.dispose();
        return;
      }

      final oldImg = _currentDecodedImage;
      _currentDecodedImage = decodedImg;
      final newExpanded = <LayoutNode>{parsedRoot};
      _expandAll(parsedRoot, newExpanded);

      state = state.copyWith(
        rawScreenshotBytes: screenshotBytes,
        decodedImage: decodedImg,
        imgWidth: decodedImg.width,
        imgHeight: decodedImg.height,
        rootNode: parsedRoot,
        xmlContent: xmlContent,
        expandedNodes: newExpanded,
        isLoading: false,
        clearError: true,
        clearSelectedNode: true,
        clearHoveredNode: true,
      );
      oldImg?.dispose();
    } on LayoutInspectorException catch (e) {
      final result = e.result;
      if (result != null && ref.mounted) {
        await ref.read(deviceRegistryProvider.notifier).syncAfterAdbResult(result);
      }
      if (currentRequestId == _requestId && ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          error: e.message,
        );
      }
    } catch (e) {
      if (currentRequestId == _requestId && ref.mounted) {
        state = state.copyWith(
          isLoading: false,
          error: e.toString(),
        );
      }
    }
  }

  /// 切换布局分析模式
  void toggleLayoutAnalysis(bool enable) {
    if (state.isLayoutAnalysis == enable) return;

    if (enable) {
      // 开启分析模式：暂停连续截图，禁止录屏，并发拉取截图与布局数据
      _autoRefreshTimer?.cancel();
      state = state.copyWith(
        isLayoutAnalysis: true,
        isAutoRefresh: false,
      );
      loadLayoutAndScreenshot();
    } else {
      // 关闭分析模式：使正在进行的请求失效，丢弃迟到结果，保留最新截图，收起左右面板与辅助工具
      _requestId++;
      state = state.copyWith(
        isLayoutAnalysis: false,
        isLoading: false,
        rootNode: null,
        xmlContent: null,
        clearSelectedNode: true,
        clearHoveredNode: true,
        showBorders: false,
        enableClickSelect: false,
        isAutoRefresh: false,
      );
    }
  }

  /// 切换连续截图
  void toggleAutoRefresh() {
    if (state.isLayoutAnalysis || state.isRecordingActive) return;

    final nextVal = !state.isAutoRefresh;
    state = state.copyWith(isAutoRefresh: nextVal);

    if (nextVal) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        captureScreenshot(isAuto: true);
      });
    } else {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    }
  }

  /// 切出 Tab 时暂停连续截图计时器（保留 state.isAutoRefresh 状态）
  void pauseAutoRefreshForTabSwitch() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  /// 切回 Tab 时根据先前的开关状态恢复连续截图
  void resumeAutoRefreshAfterTabSwitch() {
    if (state.isAutoRefresh && !state.isLayoutAnalysis && !state.isRecordingActive) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        captureScreenshot(isAuto: true);
      });
      captureScreenshot(isAuto: true);
    }
  }

  /// 切换设备或退出时重置分析模式为默认关闭
  void resetForDeviceSwitch() {
    _requestId++;
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _currentDecodedImage?.dispose();
    _currentDecodedImage = null;
    state = const ScreenshotLayoutState();
  }

  /// 启动录屏（状态补齐 starting -> recording）
  Future<void> startRecording({required BuildContext context}) async {
    if (state.isRecordingActive || state.isLayoutAnalysis) return;

    if (state.isAutoRefresh) {
      toggleAutoRefresh();
    }

    await _recordRunner?.startRecording(context: context);
  }

  /// 停止并保存录屏（状态补齐 stopping -> saving -> idle）
  Future<void> stopRecording({required BuildContext context}) async {
    await _recordRunner?.stopRecording(context: context);
  }

  // 辅助属性修改与交互方法
  void rotateLeft() {
    state = state.copyWith(rotation: (state.rotation - 90 + 360) % 360);
  }

  void rotateRight() {
    state = state.copyWith(rotation: (state.rotation + 90) % 360);
  }

  void selectNode(LayoutNode? node) {
    if (state.selectedNode == node) return;
    final newExpanded = Set<LayoutNode>.from(state.expandedNodes);
    var current = node?.parent;
    while (current != null) {
      newExpanded.add(current);
      current = current.parent;
    }
    state = state.copyWith(
      selectedNode: node,
      expandedNodes: newExpanded,
      clearSelectedNode: node == null,
    );
  }

  void hoverNode(LayoutNode? node) {
    if (state.hoveredNode == node) return;
    state = state.copyWith(
      hoveredNode: node,
      clearHoveredNode: node == null,
    );
  }

  void toggleNodeExpanded(LayoutNode node, bool expanded) {
    final newSet = Set<LayoutNode>.from(state.expandedNodes);
    if (expanded) {
      newSet.add(node);
    } else {
      newSet.remove(node);
    }
    state = state.copyWith(expandedNodes: newSet);
  }

  void expandAllNodes() {
    if (state.rootNode == null) return;
    final newSet = <LayoutNode>{};
    _expandAll(state.rootNode!, newSet);
    state = state.copyWith(expandedNodes: newSet);
  }

  void collapseAllNodes() {
    state = state.copyWith(
      expandedNodes: state.rootNode != null ? {state.rootNode!} : {},
    );
  }

  void setShowProperties(bool val) => state = state.copyWith(showProperties: val);

  void setShowBorders(bool val) {
    state = state.copyWith(
      showBorders: val,
      enableClickSelect: val ? state.enableClickSelect : false,
    );
  }

  void setEnableClickSelect(bool val) =>
      state = state.copyWith(enableClickSelect: val);

  void setUseDp(bool val) => state = state.copyWith(useDp: val);

  /// 复制当前选中节点（或根节点）的 XML 到剪贴板
  void copySelectedXml(BuildContext context) {
    ScreenshotExportHelper.copySelectedXml(
      context,
      selectedNode: state.selectedNode,
      rootNode: state.rootNode,
    );
  }

  /// 复制当前截图图片到剪贴板
  Future<void> copyScreenshotImage(BuildContext context) async {
    await ScreenshotExportHelper.copyScreenshotImage(
      context,
      bytes: state.rawScreenshotBytes,
      hostPlatform: ref.read(hostPlatformServiceProvider),
    );
  }

  /// 保存截图（若在分析模式下同时导出 XML）
  Future<void> saveScreenshotOrExport(BuildContext context) async {
    await ScreenshotExportHelper.saveScreenshotOrExport(
      context,
      deviceId: deviceId,
      rawBytes: state.rawScreenshotBytes,
      isLayoutAnalysis: state.isLayoutAnalysis,
      xmlContent: state.xmlContent,
      settings: ref.read(appSettingsProvider),
      hostPlatform: ref.read(hostPlatformServiceProvider),
    );
  }
}

/// 设备会话级 NotifierProvider.family
final screenshotLayoutControllerProvider =
    NotifierProvider.family<ScreenshotController, ScreenshotLayoutState, String>(
      ScreenshotController.new,
    );
