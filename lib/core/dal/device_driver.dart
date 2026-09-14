import 'dart:typed_data';

/// 目标硬件平台类型
enum DevicePlatform {
  /// Android 平台 (基于 ADB 协议)
  android(0),

  /// 鸿蒙 HarmonyOS 平台 (基于 HDC 协议)
  harmony(1),

  /// 苹果 iOS 平台 (基于 USB/WDA/go-ios)
  ios(2);

  const DevicePlatform(this.value);
  final int value;
}

/// 单台设备批量执行结果模型
class BatchDeviceResult {
  const BatchDeviceResult({
    required this.serial,
    required this.success,
    required this.output,
    this.error,
    required this.durationMs,
  });

  /// 目标设备唯一标识符
  final String serial;

  /// 指令执行是否成功
  final bool success;

  /// 标准输出内容
  final String output;

  /// 错误详情 (若执行失败)
  final String? error;

  /// 本次执行耗时 (毫秒)
  final int durationMs;

  factory BatchDeviceResult.fromJson(Map<String, dynamic> json) {
    return BatchDeviceResult(
      serial: json['serial'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      output: json['output'] as String? ?? '',
      error: json['error'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'serial': serial,
    'success': success,
    'output': output,
    'error': error,
    'duration_ms': durationMs,
  };
}

/// 统一跨平台设备驱动抽象基类 (Device Abstraction Layer)
abstract class DeviceDriver {
  /// 唯一设备标识符
  String get id;

  /// 目标设备所属操作系统平台
  DevicePlatform get platform;

  /// 异步执行底层控制台指令
  Future<String> executeShell(String cmd);

  /// 抓取设备全屏截图二进制字节流 (PNG 格式)
  Future<Uint8List> takeScreenshot();
}
