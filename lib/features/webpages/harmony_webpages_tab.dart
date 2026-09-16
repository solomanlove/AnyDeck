import 'package:flutter/material.dart';

import '../../core/adb/adb_device.dart';
import '../webpages/webpages_tab.dart';

/// 鸿蒙手机专属网页调试 Tab。
///
/// 复用安卓 [WebpagesTab] 的目标列表/过滤/预览/DevTools 调起 UI，底层通过
/// [WebDebugService.scanTargets] 的 `isHarmony` 参数分流走 `hdc shell cat
/// /proc/net/unix` 发现 ArkWeb devtools socket、`hdc fport` 建立转发（而非
/// adb forward）。与安卓网页调试 tab 物理隔离，便于后续追加鸿蒙 ArkWeb 专属
/// 的调试能力。
class HarmonyWebpagesTab extends StatelessWidget {
  /// 创建鸿蒙专属网页调试 Tab 实例
  const HarmonyWebpagesTab({
    super.key,
    required this.device,
    required this.isVisible,
  });

  /// 当前操作的目标鸿蒙设备
  final AdbDevice device;

  /// 当前 Tab 是否可见（控制自动刷新定时器）
  final bool isVisible;

  @override
  Widget build(BuildContext context) {
    // 复用安卓 WebpagesTab 的完整 UI；底层 Provider 已按 device.isHarmony 走 hdc。
    return WebpagesTab(device: device, isVisible: isVisible);
  }
}