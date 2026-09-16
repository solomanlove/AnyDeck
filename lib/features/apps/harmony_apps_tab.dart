part of '../dashboard_screen.dart';

/// 鸿蒙手机专属应用 Tab。
///
/// 复用安卓 [AppsTab] 的应用列表/搜索/详情/操作 UI，底层通过
/// [AppManagementService] 的 `isHarmony` 参数分流走 `bm dump`/`aa`/`bm`
/// 命令（而非 `pm`/`am`/`monkey`）。与安卓应用 tab 物理隔离，便于后续追加
/// 鸿蒙 bundle 专属的元数据（hap 路径、API 版本等）展示能力。
class HarmonyAppsTab extends StatelessWidget {
  /// 创建鸿蒙专属应用 Tab 实例
  const HarmonyAppsTab({super.key, required this.device});

  /// 当前操作的目标鸿蒙设备
  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    // 复用安卓 AppsTab 的完整 UI；底层 Provider 已根据 device.isHarmony 走 bm dump。
    return AppsTab(device: device);
  }
}