import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'posix_executable_access.dart';
import 'tool_path_resolver.dart';

/// 设置页允许替换的核心 CLI；go-ios 与 ios 共用同一个配置项。
const configurableToolNames = [
  'adb',
  'hdc',
  'ios',
  'scrcpy',
  'emulator',
  'avdmanager',
  'iproxy',
];

/// 使用稳定的本地化 key 返回校验原因，避免 UI 依赖异常描述。
class ToolPathValidationException implements Exception {
  const ToolPathValidationException(this.code);

  final String code;
}

/// 独立的每工具存储键，避免不同窗口同时修改不同工具时互相覆盖。
String toolPathPreferenceKey(String toolName) => 'settings.toolPath.$toolName';

/// 加载已保存路径；在每个 Engine 初始化服务前调用，防止首次命令使用旧路径。
Future<Map<String, String>> loadToolPathSettings({
  SharedPreferences? preferences,
}) async {
  final store = preferences ?? await SharedPreferences.getInstance();
  // 首次读取后到设置通道就绪前，其他 Engine 可能已修改持久化路径。
  await store.reload();
  final paths = <String, String>{};
  for (final tool in configurableToolNames) {
    final value = store.getString(toolPathPreferenceKey(tool))?.trim() ?? '';
    if (value.isNotEmpty) paths[tool] = value;
  }
  replaceUserToolPaths(paths);
  return Map.unmodifiable(paths);
}

/// 只接受可执行文件的绝对路径；不运行用户选择的程序进行探测。
Future<String> validateToolPath(String toolName, String value) async {
  if (!configurableToolNames.contains(toolName)) {
    throw const ToolPathValidationException('toolPathUnsupported');
  }
  final path = value.trim();
  if (path.isEmpty) return path;
  if (!File(path).isAbsolute || path.contains('\u0000')) {
    throw const ToolPathValidationException('toolPathAbsoluteRequired');
  }
  final stat = await File(path).stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const ToolPathValidationException('toolPathFileNotFound');
  }
  final executable = Platform.isWindows
      ? RegExp(r'\.(exe|com|bat|cmd)$', caseSensitive: false).hasMatch(path)
      : canExecutePosixFile(path);
  if (!executable) {
    throw const ToolPathValidationException('toolPathNotExecutable');
  }
  return path;
}
