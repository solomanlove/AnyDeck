import 'dart:io';

/// 自定义工具绝对路径覆盖字典（如应用内一键下载的 platform-tools 路径）
final Map<String, String> customToolPaths = {};

/// 注册自定义工具绝对路径
void registerCustomToolPath(String toolName, String path) {
  customToolPaths[toolName] = path;
}

/// 优先解析常见 Android 工具路径，找不到时回退到 PATH。
String resolveToolPath(String toolName) {
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
      ]
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
  return toolName;
}
