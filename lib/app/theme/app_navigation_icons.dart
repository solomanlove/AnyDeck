import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 设备侧栏图标映射；Android、HarmonyOS 与 iOS 共用同一组线框图标。
abstract final class AppNavigationIcons {
  static const IconData overview = LucideIcons.house;
  static const IconData control = LucideIcons.slidersHorizontal;
  static const IconData apps = LucideIcons.layoutGrid;
  static const IconData processes = LucideIcons.activity;
  static const IconData files = LucideIcons.folder;
  static const IconData logs = LucideIcons.fileText;
  static const IconData terminal = LucideIcons.squareTerminal;
  static const IconData web = LucideIcons.earth;
  static const IconData layout = LucideIcons.listTree;
  static const IconData capture = LucideIcons.camera;
  static const IconData performance = LucideIcons.gauge;
  static const IconData network = LucideIcons.network;
}
