part of '../dashboard_screen.dart';

/// 鸿蒙手机专属日志 Tab。
///
/// 复用安卓 [LogcatTab] 的日志展示与过滤 UI，底层通过 [LogcatController.start]
/// 的 `isHarmony` 参数分流走 `hdc hilog`（而非 `adb logcat`）。与安卓日志 tab
/// 物理隔离，便于后续追加鸿蒙 hilog 专属的域名/进程过滤能力。
class HarmonyLogcatTab extends StatelessWidget {
  /// 创建鸿蒙专属日志 Tab 实例
  const HarmonyLogcatTab({super.key, required this.device});

  /// 当前操作的目标鸿蒙设备
  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    // 复用安卓 LogcatTab 的完整 UI；底层会话已根据 device.isHarmony 走 hdc hilog。
    return LogcatTab(device: device);
  }
}
