import 'package:flutter/material.dart';

/// 一笔本地白板轨迹，点位按视频画面宽高归一化，窗口缩放后仍能对齐。
class MirrorWhiteboardStroke {
  MirrorWhiteboardStroke({required this.color, required List<Offset> points})
    : points = List.unmodifiable(points);

  final Color color;
  final List<Offset> points;
}

/// 投屏窗口独立持有的白板状态；不向设备发送事件，也不保存视频帧。
class MirrorWhiteboardController extends ChangeNotifier {
  static const maxStrokes = 200;
  static const maxPointsPerStroke = 2048;

  bool active = false;
  Color color = Colors.green;
  final List<MirrorWhiteboardStroke> _strokes = [];
  List<Offset>? _draft;
  Color? _draftColor;
  int? _pointer;
  bool? _isLandscape;

  List<MirrorWhiteboardStroke> get strokes => List.unmodifiable(_strokes);
  List<Offset>? get draft => _draft == null ? null : List.unmodifiable(_draft!);
  Color get draftColor => _draftColor ?? color;
  bool get canUndo => _draft != null || _strokes.isNotEmpty;

  /// 视频方向变化时清除旧坐标，避免旋转后标注落在错误位置。
  void updateVideoOrientation(int width, int height) {
    if (width <= 0 || height <= 0) return;
    final next = width > height;
    if (_isLandscape != null && _isLandscape != next) clear();
    _isLandscape = next;
  }

  void toggle() {
    active = !active;
    _draft = null;
    _draftColor = null;
    _pointer = null;
    notifyListeners();
  }

  void setColor(Color value) {
    color = value;
    notifyListeners();
  }

  void begin(int pointer, Offset point) {
    if (!active || _pointer != null || _strokes.length >= maxStrokes) return;
    _pointer = pointer;
    _draft = [_clamp(point)];
    _draftColor = color;
    notifyListeners();
  }

  void update(int pointer, Offset point) {
    if (_pointer != pointer || _draft == null) return;
    final next = _clamp(point);
    if ((next - _draft!.last).distanceSquared < 0.000001) return;
    if (_draft!.length >= maxPointsPerStroke) {
      _draft = [for (var i = 0; i < _draft!.length; i += 2) _draft![i]];
    }
    _draft!.add(next);
    notifyListeners();
  }

  void end(int pointer) {
    if (_pointer != pointer || _draft == null) return;
    _strokes.add(MirrorWhiteboardStroke(color: draftColor, points: _draft!));
    _draft = null;
    _draftColor = null;
    _pointer = null;
    notifyListeners();
  }

  void cancel(int pointer) {
    if (_pointer != pointer) return;
    _draft = null;
    _draftColor = null;
    _pointer = null;
    notifyListeners();
  }

  void undo() {
    if (_draft != null) {
      _draft = null;
      _draftColor = null;
      _pointer = null;
    } else if (_strokes.isNotEmpty) {
      _strokes.removeLast();
    } else {
      return;
    }
    notifyListeners();
  }

  void clear() {
    if (!canUndo) return;
    _strokes.clear();
    _draft = null;
    _draftColor = null;
    _pointer = null;
    notifyListeners();
  }

  Offset _clamp(Offset point) =>
      Offset(point.dx.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
}
