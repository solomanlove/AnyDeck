import 'package:flutter/material.dart';

import '../../core/adb/adb_device.dart';
import 'processes_tab.dart';

/// 鸿蒙手机专属进程 Tab。
///
/// 复用安卓 [ProcessesTab] 的进程列表/搜索/排序/右键菜单 UI，底层通过
/// [ProcessService.getProcesses] 的 `isHarmony` 参数分流走 HDC `top`，
/// 不支持时回退 `ps -ef`。与安卓进程 Tab 物理隔离。
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
    // 复用安卓 ProcessesTab 的完整 UI；底层根据 device.isHarmony 选择 HDC 命令。
    return ProcessesTab(device: device, isVisible: isVisible);
  }
}