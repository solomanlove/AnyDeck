import 'dart:convert';

/// 单个鼠标/手势动作帧的类型
enum RecordedActionType {
  /// 触点按下 (DOWN)
  down,

  /// 触点移动 (MOVE)
  move,

  /// 触点抬起 (UP)
  up,

  /// 触点取消 (CANCEL)
  cancel,

  /// 滚轮滚动 (SCROLL)
  scroll,
}

/// 单个鼠标/触控操作动作帧
class RecordedMouseAction {
  /// 距离录制起始点的时间偏移量（单位：毫秒）
  final int deltaMs;

  /// 动作类型
  final RecordedActionType type;

  /// 投屏设备物理坐标 X
  final int x;

  /// 投屏设备物理坐标 Y
  final int y;

  /// 录制时设备的物理宽度（用于换算归一化坐标，避免不同分辨率或窗口旋转偏移）
  final int screenWidth;

  /// 录制时设备的物理高度
  final int screenHeight;

  /// 按压力度 (0.0 ~ 1.0)
  final double pressure;

  /// 水平滚轮步长 (仅在 type == scroll 时有效, 范围 -1.0 ~ 1.0)
  final double hScroll;

  /// 垂直滚轮步长 (仅在 type == scroll 时有效, 范围 -1.0 ~ 1.0)
  final double vScroll;

  const RecordedMouseAction({
    required this.deltaMs,
    required this.type,
    required this.x,
    required this.y,
    required this.screenWidth,
    required this.screenHeight,
    this.pressure = 1.0,
    this.hScroll = 0.0,
    this.vScroll = 0.0,
  });

  /// 归一化 X 坐标 (0.0 ~ 1.0)
  double get normX => screenWidth > 0 ? (x / screenWidth).clamp(0.0, 1.0) : 0.0;

  /// 归一化 Y 坐标 (0.0 ~ 1.0)
  double get normY =>
      screenHeight > 0 ? (y / screenHeight).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
    'deltaMs': deltaMs,
    'type': type.name,
    'x': x,
    'y': y,
    'screenWidth': screenWidth,
    'screenHeight': screenHeight,
    'pressure': pressure,
    'hScroll': hScroll,
    'vScroll': vScroll,
  };

  factory RecordedMouseAction.fromJson(Map<String, dynamic> json) {
    return RecordedMouseAction(
      deltaMs: json['deltaMs'] as int? ?? 0,
      type: RecordedActionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecordedActionType.move,
      ),
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      screenWidth: json['screenWidth'] as int? ?? 0,
      screenHeight: json['screenHeight'] as int? ?? 0,
      pressure: (json['pressure'] as num?)?.toDouble() ?? 1.0,
      hScroll: (json['hScroll'] as num?)?.toDouble() ?? 0.0,
      vScroll: (json['vScroll'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// 录制完成的一组完整鼠标路径轨迹
class RecordedMouseTrack {
  /// 设备标识
  final String deviceId;

  /// 录制开始的时间
  final DateTime createdAt;

  /// 录制总时长（毫秒）
  final int totalDurationMs;

  /// 录制时设备原始宽度
  final int baseWidth;

  /// 录制时设备原始高度
  final int baseHeight;

  /// 按时间序排列的动作帧序列
  final List<RecordedMouseAction> actions;

  const RecordedMouseTrack({
    required this.deviceId,
    required this.createdAt,
    required this.totalDurationMs,
    required this.baseWidth,
    required this.baseHeight,
    required this.actions,
  });

  /// 动作帧总数
  int get actionCount => actions.length;

  /// 轨迹是否为空
  bool get isEmpty => actions.isEmpty;

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'createdAt': createdAt.toIso8601String(),
    'totalDurationMs': totalDurationMs,
    'baseWidth': baseWidth,
    'baseHeight': baseHeight,
    'actions': actions.map((a) => a.toJson()).toList(),
  };

  factory RecordedMouseTrack.fromJson(Map<String, dynamic> json) {
    return RecordedMouseTrack(
      deviceId: json['deviceId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      totalDurationMs: json['totalDurationMs'] as int? ?? 0,
      baseWidth: json['baseWidth'] as int? ?? 0,
      baseHeight: json['baseHeight'] as int? ?? 0,
      actions: (json['actions'] as List<dynamic>? ?? [])
          .map((item) =>
              RecordedMouseAction.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  String encodeJson() => jsonEncode(toJson());

  factory RecordedMouseTrack.decodeJson(String source) =>
      RecordedMouseTrack.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
