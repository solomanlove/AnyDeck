import 'package:flutter/material.dart';

import '../../core/adb/adb_device.dart';
import 'processes_tab.dart';

/// 鸿蒙手机专属进程 Tab。
///
/// 复用安卓 [ProcessesTab] 的进程列表/搜索/排序/右键菜单 UI，底层通过
/// [ProcessService.getProcesses] 的 `isHarmony` 参数分流走 `hdc shell ps -ef`
/// （而非 `adb shell top`）。与安卓进程 tab 物理隔离，便于后续追加鸿蒙专属的
/// `hidumper`/`track-jpid` 能力。
class HarmonyProcessesTab extends StatelessWidget {
  /// 创建鸿蒙专属进程 Tab 实例
  const HarmonyProcessesTab({
    super.key,
    required this.device,
    required this.isVisible,
  });

  /// 当前操作的目标鸿蒙设备
  final AdbDevice device;

  /// 当前 Tab 是否可见（控制定时刷新）
  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    // 复用安卓 ProcessesTab 的完整 UI；底层已根据 device.isHarmony 走 hdc ps -ef。
    return ProcessesTab(device: device, isVisible: isVisible);
  }
}