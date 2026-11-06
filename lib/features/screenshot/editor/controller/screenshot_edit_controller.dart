import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/screenshot_edit.dart';

/// 按编辑会话隔离工具、草稿和撤销栈；离开工作区后自动回收。
class ScreenshotEditController extends Notifier<ScreenshotEditState> {
  ScreenshotEditController(this.sessionId);

  final String sessionId;

  /// 同时限制落笔次数与每笔采样量，避免连续编辑导致内存无界增长。
  static const maxMarks = 200;
  static const maxPointsPerMark = 2048;

  @override
  ScreenshotEditState build() => ScreenshotEditState();

  void selectTool(ScreenshotEditTool value) {
    end();
    state = state.copyWith(
      tool: value,
      width: value == ScreenshotEditTool.mosaic && state.width < 36
          ? 36
          : state.width,
    );
  }

  void setColor(Color value) => state = state.copyWith(color: value);

  void setWidth(double value) {
    if (!value.isFinite) return;
    state = state.copyWith(width: value.clamp(1, 128).toDouble());
  }

  void begin(Offset point) {
    if (state.tool == ScreenshotEditTool.pan ||
        state.marks.length >= maxMarks ||
        !_isFinite(point)) {
      return;
    }
    state = state.copyWith(
      draft: ScreenshotEditMark(
        tool: state.tool,
        points: [point],
        color: state.color,
        width: state.width,
      ),
    );
  }

  void update(Offset point) {
    final mark = state.draft;
    if (mark == null || !_isFinite(point)) return;
    final isStroke =
        mark.tool == ScreenshotEditTool.pen ||
        mark.tool == ScreenshotEditTool.mosaic;
    if (!isStroke) {
      state = state.copyWith(
        draft: mark.withPoints([mark.points.first, point]),
      );
      return;
    }
    if ((point - mark.points.last).distanceSquared < 1) return;
    var points = mark.points;
    if (points.length >= maxPointsPerMark) {
      // 保留首点并等距抽稀已有轨迹，让很长的一笔仍能继续追踪鼠标末端。
      points = [for (var i = 0; i < points.length; i += 2) points[i]];
    }
    state = state.copyWith(draft: mark.withPoints([...points, point]));
  }

  void end() {
    final mark = state.draft;
    if (mark == null) return;
    final isShape =
        mark.tool == ScreenshotEditTool.rectangle ||
        mark.tool == ScreenshotEditTool.ellipse ||
        mark.tool == ScreenshotEditTool.cover;
    if (isShape && (mark.points.length < 2 || mark.rect.isEmpty)) {
      cancelStroke();
      return;
    }
    state = state.copyWith(
      marks: [...state.marks, mark],
      redoMarks: [],
      clearDraft: true,
    );
  }

  void cancelStroke() => state = state.copyWith(clearDraft: true);

  void undo() {
    if (state.draft != null) {
      cancelStroke();
      return;
    }
    if (state.marks.isEmpty) return;
    state = state.copyWith(
      marks: state.marks.sublist(0, state.marks.length - 1),
      redoMarks: [...state.redoMarks, state.marks.last],
    );
  }

  void redo() {
    if (!state.canRedo) return;
    state = state.copyWith(
      marks: [...state.marks, state.redoMarks.last],
      redoMarks: state.redoMarks.sublist(0, state.redoMarks.length - 1),
    );
  }

  /// 清空当前会话标注和历史；保留用户选择的工具样式。
  void clear() =>
      state = state.copyWith(marks: [], redoMarks: [], clearDraft: true);

  bool _isFinite(Offset point) => point.dx.isFinite && point.dy.isFinite;
}

final screenshotEditControllerProvider = NotifierProvider.autoDispose
    .family<ScreenshotEditController, ScreenshotEditState, String>(
      ScreenshotEditController.new,
    );
