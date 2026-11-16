import 'dart:io';

import 'posix_executable_access.dart';

/// 自定义工具绝对路径覆盖字典（如应用内一键下载的 platform-tools 路径）
final Map<String, String> customToolPaths = {};

/// 用户显式选择优先于应用自动下载的路径；恢复默认不会丢弃下载记录。
final Map<String, String> _userToolPaths = {};

String _toolKey(String toolName) => toolName == 'go-ios' ? 'ios' : toolName;

/// 应用持久化设置或跨窗口快照，既有服务随后解析到同一份路径。
void replaceUserToolPaths(Map<String, String> paths) {
  _userToolPaths
    ..clear()
    ..addAll(paths);
}

/// 原生 DAL 使用固定环境时，让自定义 CLI 配置优先。
bool hasUserToolPath(String toolName) =>
    _userToolPaths.containsKey(_toolKey(toolName));

/// 注册自定义工具绝对路径
void registerCustomToolPath(String toolName, String path) {
  customToolPaths[toolName] = path;
}

/// 优先解析常见 Android 工具路径，找不到时回退到 PATH。
String resolveToolPath(String toolName) {
  final userPath = _userToolPaths[_toolKey(toolName)];
  if (userPath != null) return userPath;

  if (customToolPaths.containsKey(toolName)) {
    final custom = customToolPaths[toolName]!;
    if (File(custom).existsSync()) return custom;
  }

  final sdkRoot =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  final candidates = <String>[
    // 优先检查应用内置下载的 platform-tools 工具目录
    if (toolName == 'adb' && home != null) ...[
      '$home/Library/Application Support/AnyDeck/tools/platform-tools/adb',
      '$home/Library/Application Support/com.example.adbManage/tools/platform-tools/adb',
      '$home/AppData/Roaming/AnyDeck/tools/platform-tools/adb.exe',
      '$home/.local/share/AnyDeck/tools/platform-tools/adb',
      '$home/Library/Caches/AnyDeck/tools/platform-tools/adb',
    ],
    if (toolName == 'adb' && sdkRoot != null) '$sdkRoot/platform-tools/adb',
    if (toolName == 'adb' && home != null)
      '$home/Library/Android/sdk/platform-tools/adb',
    if (toolName == 'emulator' && sdkRoot != null) ...[
      '$sdkRoot/emulator/emulator',
      '$sdkRoot/emulator/emulator.exe',
    ],
    if (toolName == 'emulator' && home != null) ...[
      '$home/Library/Android/sdk/emulator/emulator',
      '$home/AppData/Local/Android/Sdk/emulator/emulator.exe',
    ],
    if (toolName == 'avdmanager' && sdkRoot != null) ...[
      '$sdkRoot/cmdline-tools/latest/bin/avdmanager',
      '$sdkRoot/tools/bin/avdmanager',
    ],
    if (toolName == 'avdmanager' && home != null) ...[
      '$home/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager',
      '$home/Library/Android/sdk/tools/bin/avdmanager',
      '$home/AppData/Local/Android/Sdk/cmdline-tools/latest/bin/avdmanager.bat',
      '$home/AppData/Local/Android/Sdk/tools/bin/avdmanager.bat',
    ],
    if (toolName == 'scrcpy') '/opt/homebrew/bin/scrcpy',
    if (toolName == 'scrcpy') '/usr/local/bin/scrcpy',
    if (toolName == 'go-ios' || toolName == 'ios') ...[
      '/opt/homebrew/bin/ios',
      '/usr/local/bin/ios',
      '/opt/homebrew/bin/go-ios',
      '/usr/local/bin/go-ios',
      if (home != null) ...[
        '$home/go/bin/ios',
        '$home/go/bin/go-ios',
        '$home/Library/Application Support/AnyDeck/tools/ios/ios',
      ],
    ],
    if (toolName == 'hdc') ...[
      if (Platform.environment['HUAWEI_SDK_HOME'] != null)
        '${Platform.environment['HUAWEI_SDK_HOME']}/openharmony/toolchains/hdc',
      if (Platform.environment['OHOS_SDK_HOME'] != null)
        '${Platform.environment['OHOS_SDK_HOME']}/openharmony/toolchains/hdc',
      if (home != null) ...[
        '$home/Library/Huawei/Sdk/openharmony/toolchains/hdc',
        '$home/AppData/Local/Huawei/Sdk/openharmony/toolchains/hdc',
        '$home/AppData/Local/Huawei/Sdk/openharmony/toolchains/hdc.exe',
        '$home/Library/Application Support/AnyDeck/tools/harmony/hdc',
      ],
      '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc',
      '/Applications/DevEco-Studio.app/Contents/tools/hdc',
    ],
    '/opt/homebrew/bin/$toolName',
    '/usr/local/bin/$toolName',
    '/usr/bin/$toolName',
  ];

  for (final path in candidates) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  // PATH 中的绝对路径同时供命令执行、目录与终端入口使用。
  return resolveToolFromPath(toolName) ?? toolName;
}

/// 不启动 shell，按宿主 PATH / PATHEXT 定位可执行文件。
String? resolveToolFromPath(String toolName, {String? searchPath}) {
  final extensions = Platform.isWindows
      ? [
          '',
          ...(Platform.environment['PATHEXT'] ?? '.EXE;.COM;.BAT;.CMD').split(
            ';',
          ),
        ]
      : [''];
  for (final entry in (searchPath ?? Platform.environment['PATH'] ?? '').split(
    Platform.isWindows ? ';' : ':',
  )) {
    if (entry.isEmpty) continue;
    final directory = entry.replaceAll(RegExp(r'^"|"$'), '');
    for (final extension in extensions) {
      final file = File(
        '$directory${Platform.pathSeparator}$toolName$extension',
      );
      final stat = file.statSync();
      if (stat.type == FileSystemEntityType.file &&
          (Platform.isWindows || canExecutePosixFile(file.path))) {
        return file.absolute.path;
      }
    }
  }
  return null;
}
