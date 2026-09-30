part of '../dashboard_screen.dart';

/// 模拟器项数据包装类，合并模拟器配置和当前状态。
class _EmulatorItem {
  const _EmulatorItem({
    required this.emulator,
    required this.status,
    this.deviceId,
    this.launch,
  });

  /// 模拟器配置属性
  final AndroidEmulator emulator;

  /// 模拟器运行状态 ('running', 'starting', 'stopped', 'error')
  final String status;

  /// 启动诊断保留到下次重试；错误详情可在列表中查看。
  final EmulatorLaunchState? launch;

  /// 如果运行中，对应的 ADB 设备 ID
  final String? deviceId;

  /// 已停止或失败且进程已退出时允许重试。
  bool get canStart =>
      (status == 'stopped' || status == 'error') &&
      launch?.processAlive != true &&
      deviceId == null;

  /// 仅在确认进程已停止时允许清除数据。
  bool get canClearData => canStart;

  /// 仅在确认进程已停止时允许删除。
  bool get canDelete => canStart;
}
