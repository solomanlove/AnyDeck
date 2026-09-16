import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/adb/adb_device.dart';
import 'terminal_tab.dart';

/// 鸿蒙手机专属终端 Tab。
///
/// 复用安卓 [TerminalTab] 的交互式终端 UI，底层通过 [AdbTerminalSession.isHarmony]
/// 分流走 `hdc shell`（而非 `adb shell`）。与安卓终端 tab 物理隔离，便于后续
/// 追加鸿蒙专属能力（如 `hdc shell -b <bundle>` 进入应用沙箱）。
class HarmonyTerminalTab extends StatelessWidget {
  /// 创建鸿蒙专属终端 Tab 实例
  const HarmonyTerminalTab({super.key, required this.device});

  /// 当前操作的目标鸿蒙设备
  final AdbDevice device;

  @override
  Widget build(BuildContext context) {
    // 复用安卓 TerminalTab 的完整 UI；底层会话已根据 device.isHarmony 走 hdc shell。
    return TerminalTab(device: device);
  }
}