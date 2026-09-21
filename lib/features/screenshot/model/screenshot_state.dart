import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../core/layout_inspector/layout_node.dart';

/// 录屏生命周期状态枚举。
enum ScreenRecordPhase {
  /// 空闲状态
  idle,

  /// 正在启动录屏进程
  starting,

  /// 正在录制中
  recording,

  /// 正在停止录屏进程
  stopping,

  /// 正在拉取并保存录屏文件
  saving,
}

/// 截图与布局分析统一状态模型。
class ScreenshotLayoutState {
  const ScreenshotLayoutState({
    this.rawScreenshotBytes,
    this.decodedImage,
    this.imgWidth = 0,
    this.imgHeight = 0,
    this.rotation = 0,
    this.isLayoutAnalysis = false,
    this.isAutoRefresh = false,
    this.isAutoSave = false,
    this.autoSavePath = '',
    this.autoRefreshInterval = 3,
    this.autoSavedCount = 0,
    this.showProperties = true,
    this.showBorders = false,
    this.enableClickSelect = false,
    this.useDp = true,
    this.rootNode,
    this.xmlContent,
    this.selectedNode,
    this.hoveredNode,
    this.expandedNodes = const {},
    this.isLoading = false,
    this.error,
    this.recordPhase = ScreenRecordPhase.idle,
    this.recordDuration = 0,
  });

  /// 原始截图二进制数据 (PNG)
  final Uint8List? rawScreenshotBytes;

  /// 已解码用于 Canvas 渲染与坐标定位的图片对象
  final ui.Image? decodedImage;

  /// 截图原始宽度
  final int imgWidth;

  /// 截图原始高度
  final int imgHeight;

  /// 旋转角度 (0, 90, 180, 270)
  final int rotation;

  /// 布局分析模式是否开启
  final bool isLayoutAnalysis;

  /// 是否开启连续截图（自动刷新）
  final bool isAutoRefresh;

  /// 是否在自动刷新时自动保存截图到指定文件夹
  final bool isAutoSave;

  /// 自动保存截图的目标文件夹绝对路径（为空时回退默认保存路径）
  final String autoSavePath;

  /// 自动刷新间隔（秒，默认 3 秒）
  final int autoRefreshInterval;

  /// 当前自动刷新会话已自动保存的截图数量
  final int autoSavedCount;

  /// 是否显示右侧属性面板
  final bool showProperties;

  /// 是否在画布上绘制所有节点边框
  final bool showBorders;

  /// 是否开启点击屏幕选择节点
  final bool enableClickSelect;

  /// 坐标与尺寸是否使用 dp 作为单位
  final bool useDp;

  /// 布局分析解析出的根节点
  final LayoutNode? rootNode;

  /// 原始 XML 内容
  final String? xmlContent;

  /// 当前选中的布局节点
  final LayoutNode? selectedNode;

  /// 当前鼠标悬停的布局节点
  final LayoutNode? hoveredNode;

  /// 当前已展开的树节点集合
  final Set<LayoutNode> expandedNodes;

  /// 是否正在加载中（包含截图拉取或布局转储）
  final bool isLoading;

  /// 错误提示信息
  final String? error;

  /// 当前录屏生命周期阶段
  final ScreenRecordPhase recordPhase;

  /// 已录制时长（秒）
  final int recordDuration;

  /// 是否处于任意录屏活跃阶段（启动、录制、停止、保存）
  bool get isRecordingActive => recordPhase != ScreenRecordPhase.idle;

  /// 只有不在录屏任何阶段时，才允许切换布局分析模式
  bool get canToggleLayoutAnalysis => !isRecordingActive;

  /// 获取不可切换布局分析的原因国际化 key
  String? get cannotToggleReasonKey {
    return switch (recordPhase) {
      ScreenRecordPhase.starting => 'recordingStartingDisableLayout',
      ScreenRecordPhase.recording => 'recordingDisableLayoutAnalysis',
      ScreenRecordPhase.stopping => 'recordingStoppingDisableLayout',
      ScreenRecordPhase.saving => 'recordingSavingDisableLayout',
      ScreenRecordPhase.idle => null,
    };
  }

  /// 截图文件大小格式化文案
  String get sizeLabel {
    if (rawScreenshotBytes == null) return '';
    final bytes = rawScreenshotBytes!.length;
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
  }

  /// 是否已有画面展示
  bool get hasImage => decodedImage != null || rawScreenshotBytes != null;

  ScreenshotLayoutState copyWith({
    Uint8List? rawScreenshotBytes,
    ui.Image? decodedImage,
    int? imgWidth,
    int? imgHeight,
    int? rotation,
    bool? isLayoutAnalysis,
    bool? isAutoRefresh,
    bool? isAutoSave,
    String? autoSavePath,
    int? autoRefreshInterval,
    int? autoSavedCount,
    bool? showProperties,
    bool? showBorders,
    bool? enableClickSelect,
    bool? useDp,
    LayoutNode? rootNode,
    String? xmlContent,
    LayoutNode? selectedNode,
    LayoutNode? hoveredNode,
    Set<LayoutNode>? expandedNodes,
    bool? isLoading,
    String? error,
    ScreenRecordPhase? recordPhase,
    int? recordDuration,
    bool clearSelectedNode = false,
    bool clearHoveredNode = false,
    bool clearError = false,
  }) {
    return ScreenshotLayoutState(
      rawScreenshotBytes: rawScreenshotBytes ?? this.rawScreenshotBytes,
      decodedImage: decodedImage ?? this.decodedImage,
      imgWidth: imgWidth ?? this.imgWidth,
      imgHeight: imgHeight ?? this.imgHeight,
      rotation: rotation ?? this.rotation,
      isLayoutAnalysis: isLayoutAnalysis ?? this.isLayoutAnalysis,
      isAutoRefresh: isAutoRefresh ?? this.isAutoRefresh,
      isAutoSave: isAutoSave ?? this.isAutoSave,
      autoSavePath: autoSavePath ?? this.autoSavePath,
      autoRefreshInterval: autoRefreshInterval ?? this.autoRefreshInterval,
      autoSavedCount: autoSavedCount ?? this.autoSavedCount,
      showProperties: showProperties ?? this.showProperties,
      showBorders: showBorders ?? this.showBorders,
      enableClickSelect: enableClickSelect ?? this.enableClickSelect,
      useDp: useDp ?? this.useDp,
      rootNode: rootNode ?? this.rootNode,
      xmlContent: xmlContent ?? this.xmlContent,
      selectedNode: clearSelectedNode ? null : (selectedNode ?? this.selectedNode),
      hoveredNode: clearHoveredNode ? null : (hoveredNode ?? this.hoveredNode),
      expandedNodes: expandedNodes ?? this.expandedNodes,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      recordPhase: recordPhase ?? this.recordPhase,
      recordDuration: recordDuration ?? this.recordDuration,
    );
  }
}
