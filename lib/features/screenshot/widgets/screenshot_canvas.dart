import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../core/layout_inspector/layout_node.dart';
import 'screen_preview_painter.dart';

/// 截图与布局分析共享中央画布组件。
/// 支持 InteractiveViewer 缩放与平移，在左右面板开合引起视口尺寸变化时自适应居中适配，且保留当前的旋转角度。
class ScreenshotCanvas extends StatefulWidget {
  const ScreenshotCanvas({
    super.key,
    required this.decodedImage,
    required this.rotationAngle,
    required this.transformationController,
    required this.isLayoutAnalysis,
    this.rootNode,
    this.selectedNode,
    this.hoveredNode,
    this.showBorders = false,
    this.enableClickSelect = false,
    this.useDp = true,
    this.deviceScale = 1.0,
    this.isLoading = false,
    this.onNodeSelected,
    this.onNodeHovered,
    this.onViewportSizeChanged,
  });

  /// 已解码待渲染图片
  final ui.Image? decodedImage;

  /// 旋转度数 (0, 90, 180, 270)
  final int rotationAngle;

  /// 外部传入的统一变换控制器
  final TransformationController transformationController;

  /// 当前是否处于布局分析模式
  final bool isLayoutAnalysis;

  /// 布局树根节点
  final LayoutNode? rootNode;

  /// 当前选中节点
  final LayoutNode? selectedNode;

  /// 当前悬停节点
  final LayoutNode? hoveredNode;

  /// 是否绘制全量组件线框
  final bool showBorders;

  /// 是否开启点击屏幕选择节点
  final bool enableClickSelect;

  /// 是否使用 dp 单位
  final bool useDp;

  /// 屏幕逻辑缩放比率
  final double deviceScale;

  /// 是否处于后台加载状态
  final bool isLoading;

  /// 节点选中回调
  final ValueChanged<LayoutNode?>? onNodeSelected;

  /// 节点悬停回调
  final ValueChanged<LayoutNode?>? onNodeHovered;

  /// 视口尺寸变化回调
  final ValueChanged<Size>? onViewportSizeChanged;

  @override
  State<ScreenshotCanvas> createState() => ScreenshotCanvasState();
}

class ScreenshotCanvasState extends State<ScreenshotCanvas> {
  Size? _lastSize;
  ui.Image? _lastImage;
  int? _lastRotation;

  /// 适应窗口居中重置缩放与平移，保留当前旋转角度
  void resetZoomAndPan(Size viewportSize) {
    if (widget.decodedImage == null) return;
    final imageWidth = widget.decodedImage!.width.toDouble();
    final imageHeight = widget.decodedImage!.height.toDouble();
    final rotatedW = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? imageHeight
        : imageWidth;
    final rotatedH = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? imageWidth
        : imageHeight;

    final scale = min(
      viewportSize.width / rotatedW,
      viewportSize.height / rotatedH,
    );
    final renderedW = rotatedW * scale;
    final renderedH = rotatedH * scale;
    final offsetX = (viewportSize.width - renderedW) / 2;
    final offsetY = (viewportSize.height - renderedH) / 2;

    widget.transformationController.value = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      // ignore: deprecated_member_use
      ..scale(scale);

    widget.onViewportSizeChanged?.call(viewportSize);
  }

  /// 缩放指定倍数
  void zoom(double factor) {
    final currentMatrix = widget.transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();
    final targetScale = currentScale * factor;
    if (targetScale < 0.05 || targetScale > 10.0) return;

    final viewportWidth = _lastSize?.width ?? 400.0;
    final viewportHeight = _lastSize?.height ?? 800.0;
    final center = Offset(viewportWidth / 2, viewportHeight / 2);
    final translation = currentMatrix.getTranslation();
    final newTx = center.dx * (1 - factor) + translation.x * factor;
    final newTy = center.dy * (1 - factor) + translation.y * factor;

    widget.transformationController.value = Matrix4.copy(currentMatrix)
      ..setTranslationRaw(newTx, newTy, 0.0)
      // ignore: deprecated_member_use
      ..scale(factor);
  }

  /// 1:1 原始像素缩放
  void zoom1to1() {
    if (widget.decodedImage == null) return;
    final imageWidth = widget.decodedImage!.width.toDouble();
    final imageHeight = widget.decodedImage!.height.toDouble();
    final rotatedW = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? imageHeight
        : imageWidth;
    final rotatedH = (widget.rotationAngle == 90 || widget.rotationAngle == 270)
        ? imageWidth
        : imageHeight;

    final viewportWidth = _lastSize?.width ?? 400.0;
    final viewportHeight = _lastSize?.height ?? 800.0;
    final offsetX = (viewportWidth - rotatedW) / 2;
    final offsetY = (viewportHeight - rotatedH) / 2;

    widget.transformationController.value = Matrix4.identity()
      ..setTranslationRaw(offsetX, offsetY, 0.0)
      // ignore: deprecated_member_use
      ..scale(1.0);
  }

  /// 递归查找坐标点下最深层的叶子节点
  LayoutNode? _findDeepestNodeAt(LayoutNode node, Offset nativePoint) {
    final rect = node.rect;
    if (rect != null && !rect.contains(nativePoint)) {
      return null;
    }

    for (final child in node.children.reversed) {
      final found = _findDeepestNodeAt(child, nativePoint);
      if (found != null) {
        return found;
      }
    }

    return rect != null ? node : null;
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.decodedImage;
    if (image == null) {
      return widget.isLoading
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final viewportHeight = constraints.maxHeight;
        if (viewportWidth <= 0 || viewportHeight <= 0) {
          return const SizedBox.shrink();
        }

        final currentSize = Size(viewportWidth, viewportHeight);

        // 视口尺寸、图片或旋转度数变化时，自动重新自适应居中，保留旋转度数
        if (_lastSize != currentSize ||
            _lastImage != image ||
            _lastRotation != widget.rotationAngle) {
          _lastSize = currentSize;
          _lastImage = image;
          _lastRotation = widget.rotationAngle;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              resetZoomAndPan(currentSize);
            }
          });
        }

        final imageWidth = image.width.toDouble();
        final imageHeight = image.height.toDouble();
        final rotatedW =
            (widget.rotationAngle == 90 || widget.rotationAngle == 270)
            ? imageHeight
            : imageWidth;
        final rotatedH =
            (widget.rotationAngle == 90 || widget.rotationAngle == 270)
            ? imageWidth
            : imageHeight;

        final fitScale = min(
          viewportWidth / rotatedW,
          viewportHeight / rotatedH,
        );
        final minScaleVal = min(max(0.01, fitScale * 0.8), 1.0);
        final marginX = max(400.0, (viewportWidth / minScaleVal - rotatedW) / 2);
        final marginY = max(400.0, (viewportHeight / minScaleVal - rotatedH) / 2);

        // 局部视口坐标逆向映射为 Android 物理设备坐标
        Offset localToNative(Offset localPoint) {
          final cx = localPoint.dx - rotatedW / 2;
          final cy = localPoint.dy - rotatedH / 2;
          final rad = -widget.rotationAngle * pi / 180;
          final rx = cx * cos(rad) - cy * sin(rad);
          final ry = cx * sin(rad) + cy * cos(rad);
          return Offset(rx + imageWidth / 2, ry + imageHeight / 2);
        }

        LayoutNode? getNodeAtLocalPoint(Offset localPoint) {
          if (widget.rootNode == null) return null;
          final nativePoint = localToNative(localPoint);
          return _findDeepestNodeAt(widget.rootNode!, nativePoint);
        }

        final isInteractiveSelection =
            widget.isLayoutAnalysis && widget.showBorders;

        return Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: widget.transformationController,
                boundaryMargin: EdgeInsets.symmetric(
                  horizontal: marginX,
                  vertical: marginY,
                ),
                minScale: minScaleVal,
                maxScale: 10.0,
                constrained: false,
                child: SizedBox(
                  width: rotatedW,
                  height: rotatedH,
                  child: MouseRegion(
                    cursor: isInteractiveSelection
                        ? SystemMouseCursors.click
                        : MouseCursor.defer,
                    onHover: (event) {
                      if (!isInteractiveSelection) return;
                      final RenderBox? viewportBox =
                          context.findRenderObject() as RenderBox?;
                      if (viewportBox == null) return;
                      final viewportPoint = viewportBox.globalToLocal(
                        event.position,
                      );
                      final localPoint = widget.transformationController.toScene(
                        viewportPoint,
                      );
                      final node = getNodeAtLocalPoint(localPoint);
                      widget.onNodeHovered?.call(node);
                    },
                    onExit: (_) {
                      if (!isInteractiveSelection) return;
                      widget.onNodeHovered?.call(null);
                    },
                    child: GestureDetector(
                      onTapDown: (details) {
                        if (!isInteractiveSelection) return;
                        final RenderBox? viewportBox =
                            context.findRenderObject() as RenderBox?;
                        if (viewportBox == null) return;
                        final viewportPoint = viewportBox.globalToLocal(
                          details.globalPosition,
                        );
                        final localPoint = widget.transformationController.toScene(
                          viewportPoint,
                        );
                        final nativePoint = localToNative(localPoint);
                        final node = widget.rootNode == null
                            ? null
                            : _findDeepestNodeAt(widget.rootNode!, nativePoint);
                        widget.onNodeSelected?.call(node);
                      },
                      child: SizedBox.expand(
                        child: CustomPaint(
                          painter: ScreenPreviewPainter(
                            image: image,
                            rootNode: widget.isLayoutAnalysis ? widget.rootNode : null,
                            selectedNode: widget.isLayoutAnalysis
                                ? widget.selectedNode
                                : null,
                            hoveredNode: widget.isLayoutAnalysis
                                ? widget.hoveredNode
                                : null,
                            showBorders: widget.isLayoutAnalysis && widget.showBorders,
                            rotationAngle: widget.rotationAngle,
                            useDp: widget.useDp,
                            deviceScale: widget.deviceScale,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}
