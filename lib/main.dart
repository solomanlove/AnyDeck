import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/adb_manage_app.dart';

/// 应用入口，ProviderScope 负责承载全局 Riverpod 依赖图。
void main() {
  runApp(const ProviderScope(child: AdbManageApp()));
}
