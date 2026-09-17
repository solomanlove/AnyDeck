import 'dart:typed_data';
import '../models/recorded_mouse_action.dart';

/// 鼠标操作轨迹控制协议序列化工具
class MouseTrackSerializer {
  const MouseTrackSerializer._();

  /// 浮点数转定点数（用于 Scrcpy 滚轮精度编码）
  static int _floatToFixedPoint(double val) {
    if (val >= 1.0) return 32767;
    if (val <= -1.0) return -32768;
    return (val * (val < 0 ? 32768 : 32767)).toInt();
  }

  /// 序列化触控事件为 Scrcpy 二进制控制协议包 (type = 2)
  ///
  /// [action]: 0 (DOWN), 1 (UP), 2 (MOVE), 3 (CANCEL)
  /// [pointerId]: 触点 ID (默认 0)
  /// [x], [y]: 目标设备物理坐标
  /// [screenWidth], [screenHeight]: 目标设备分辨率
  /// [pressure]: 触控压力值 (0 ~ 65535)
  /// [buttons]: 鼠标按键掩码
  static Uint8List serializeTouchEvent({
    required int action,
    int pointerId = 0,
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    int pressure = 65535,
    int buttons = 0,
  }) {
    final buffer = ByteData(32);
    buffer.setUint8(0, 2); // type = 2 (touch)
    buffer.setUint8(1, action);
    buffer.setUint64(2, pointerId, Endian.big);
    buffer.setUint32(10, x, Endian.big);
    buffer.setUint32(14, y, Endian.big);
    buffer.setUint16(18, screenWidth, Endian.big);
    buffer.setUint16(20, screenHeight, Endian.big);
    buffer.setUint16(22, pressure, Endian.big);
    buffer.setUint32(24, 0, Endian.big); // actionButton = 0
    buffer.setUint32(28, buttons, Endian.big);
    return buffer.buffer.asUint8List(0, 32);
  }

  /// 序列化滚轮事件为 Scrcpy 二进制控制协议包 (type = 3)
  static Uint8List serializeScrollEvent({
    required int x,
    required int y,
    required int screenWidth,
    required int screenHeight,
    required double hScroll,
    required double vScroll,
  }) {
    final buffer = ByteData(21);
    buffer.setUint8(0, 3); // type = 3 (scroll)
    buffer.setUint32(1, x, Endian.big);
    buffer.setUint32(5, y, Endian.big);
    buffer.setUint16(9, screenWidth, Endian.big);
    buffer.setUint16(11, screenHeight, Endian.big);
    buffer.setInt16(13, _floatToFixedPoint(hScroll), Endian.big);
    buffer.setInt16(15, _floatToFixedPoint(vScroll), Endian.big);
    buffer.setUint32(17, 0, Endian.big); // buttons
    return buffer.buffer.asUint8List(0, 21);
  }

  /// 将录制的动作帧直接转换为可发送的控制协议二进制数据
  ///
  /// [currentWidth], [currentHeight]: 当前设备分辨率，若未提供则使用帧内录制的原始分辨率
  static Uint8List? serializeAction(
    RecordedMouseAction action, {
    int? currentWidth,
    int? currentHeight,
  }) {
    final w = (currentWidth != null && currentWidth > 0)
        ? currentWidth
        : action.screenWidth;
    final h = (currentHeight != null && currentHeight > 0)
        ? currentHeight
        : action.screenHeight;

    // 根据当前分辨率与录制时的归一化比例动态计算真实 x, y，确保窗口拉伸或分辨率变动时不漂移
    final targetX = (action.normX * w).round();
    final targetY = (action.normY * h).round();

    switch (action.type) {
      case RecordedActionType.down:
        return serializeTouchEvent(
          action: 0,
          x: targetX,
          y: targetY,
          screenWidth: w,
          screenHeight: h,
          pressure: (action.pressure * 65535).round().clamp(1, 65535),
        );
      case RecordedActionType.up:
        return serializeTouchEvent(
          action: 1,
          x: targetX,
          y: targetY,
          screenWidth: w,
          screenHeight: h,
          pressure: 0,
        );
      case RecordedActionType.move:
        return serializeTouchEvent(
          action: 2,
          x: targetX,
          y: targetY,
          screenWidth: w,
          screenHeight: h,
          pressure: (action.pressure * 65535).round().clamp(1, 65535),
        );
      case RecordedActionType.cancel:
        return serializeTouchEvent(
          action: 3,
          x: targetX,
          y: targetY,
          screenWidth: w,
          screenHeight: h,
          pressure: 0,
        );
      case RecordedActionType.scroll:
        return serializeScrollEvent(
          x: targetX,
          y: targetY,
          screenWidth: w,
          screenHeight: h,
          hScroll: action.hScroll,
          vScroll: action.vScroll,
        );
    }
  }
}
