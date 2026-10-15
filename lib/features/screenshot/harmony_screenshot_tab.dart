import 'package:flutter/widgets.dart';

import '../../core/adb/adb_device.dart';
import 'dashboard_screenshot_tab.dart';

/// HarmonyOS 截图、录屏与布局分析入口。
///
/// 平台命令由共享 Controller 和 LayoutInspectorService 分流，页面复用统一的三栏 Inspector。
class HarmonyScreenshotTab extends StatelessWidget {
  const HarmonyScreenshotTab({super.key, required this.device});

  final AdbDevice device;

  @override
  Widget build(BuildContext context) => DashboardScreenshotTab(device: device);
}
