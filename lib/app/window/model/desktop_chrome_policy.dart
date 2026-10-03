import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 集中描述宿主系统的窗口装饰策略，与连接设备的 Android/iOS 平台无关。
class DesktopChromePolicy {
  const DesktopChromePolicy(this.platform);

  final TargetPlatform platform;

  static DesktopChromePolicy get current =>
      DesktopChromePolicy(defaultTargetPlatform);

  bool get usesMacChrome => !kIsWeb && platform == TargetPlatform.macOS;
  bool get usesCustomCaption => !kIsWeb && platform == TargetPlatform.windows;

  /// Linux 由桌面环境决定按钮位置、装饰及窗口菜单。
  TitleBarStyle get mainTitleBarStyle => usesMacChrome || usesCustomCaption
      ? TitleBarStyle.hidden
      : TitleBarStyle.normal;

  /// 子窗口保留系统控制，避免改变投屏客户区内的工具栏与坐标关系。
  TitleBarStyle get subWindowTitleBarStyle =>
      usesMacChrome ? TitleBarStyle.hidden : TitleBarStyle.normal;

  double get sidebarTopInset => usesMacChrome ? 36 : 14;
  double get toolbarLeadingInset => usesMacChrome ? 80 : 0;
}
