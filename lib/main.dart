import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/adb_manage_app.dart';
import 'app/window/desktop_window_manager_service.dart';

/// 应用入口，ProviderScope 负责承载全局 Riverpod 依赖图。
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopWindowManagerService.initialize();

  runApp(const ProviderScope(child: AdbManageApp()));
}
