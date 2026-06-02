import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/adb_manage_app.dart';
import 'app/window/desktop_window_manager_service.dart';
import 'app/window/emulator_manager_window_app.dart';

/// 应用入口，ProviderScope 负责承载全局 Riverpod 依赖图。
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args[2].isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(args[2]) as Map<String, dynamic>;

    runApp(
      ProviderScope(
        child: EmulatorManagerWindowApp(
          windowId: windowId,
          argument: argument,
        ),
      ),
    );
    return;
  }

  await DesktopWindowManagerService.initialize();

  runApp(const ProviderScope(child: AdbManageApp()));
}
