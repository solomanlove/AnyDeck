import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 图片编辑工具；pan 将鼠标拖动交回截图画布，其余工具使用原图像素坐标。
enum ScreenshotEditTool { pan, rectangle, ellipse, pen, mosaic, cover }

/// 一次落笔的不可变标注，points、width 均使用原图像素，color 不随 UI Theme 改色。
class ScreenshotEditMark {
  ScreenshotEditMark({
    required this.tool,
    required List<Offset> points,
    required this.color,
    required this.width,
  }) : points = List.unmodifiable(points);

  final ScreenshotEditTool tool;
  final List<Offset> points;
  final Color color;
  final double width;

  Rect get rect => Rect.fromPoints(points.first, points.last);

  ScreenshotEditMark withPoints(List<Offset> value) =>
      ScreenshotEditMark(tool: tool, points: value, color: color, width: width);
}

/// 编辑会话仅保存标注与历史；原图和 PNG 不进入撤销栈，避免整图重复占用内存。
class ScreenshotEditState {
  ScreenshotEditState({
    this.tool = ScreenshotEditTool.rectangle,
    this.color = Colors.red,
    this.width = 6,
    List<ScreenshotEditMark> marks = const [],
    List<ScreenshotEditMark> redoMarks = const [],
    this.draft,
  }) : marks = List.unmodifiable(marks),
       redoMarks = List.unmodifiable(redoMarks);

  final ScreenshotEditTool tool;
  final Color color;
  final double width;
  final List<ScreenshotEditMark> marks;
  final List<ScreenshotEditMark> redoMarks;
  final ScreenshotEditMark? draft;

  bool get isDirty => marks.isNotEmpty || draft != null;
  bool get canUndo => marks.isNotEmpty || draft != null;
  bool get canRedo => redoMarks.isNotEmpty && draft == null;

  ScreenshotEditState copyWith({
    ScreenshotEditTool? tool,
    Color? color,
    double? width,
    List<ScreenshotEditMark>? marks,
    List<ScreenshotEditMark>? redoMarks,
    ScreenshotEditMark? draft,
    bool clearDraft = false,
  }) => ScreenshotEditState(
    tool: tool ?? this.tool,
    color: color ?? this.color,
    width: width ?? this.width,
    marks: marks ?? this.marks,
    redoMarks: redoMarks ?? this.redoMarks,
    draft: clearDraft ? null : draft ?? this.draft,
  );
}

/// 完成编辑后交给截图 Controller 的结果；调用方取得 image 的释放责任。
class ScreenshotEditResult {
  const ScreenshotEditResult({required this.bytes, required this.image});

  final Uint8List bytes;
  final ui.Image image;
}
