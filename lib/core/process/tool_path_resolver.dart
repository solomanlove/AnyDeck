import 'dart:io';

/// 优先解析常见 Android 工具路径，找不到时回退到 PATH。
String resolveToolPath(String toolName) {
  final sdkRoot =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  final candidates = <String>[
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
    if (toolName == 'scrcpy') '/opt/homebrew/bin/scrcpy',
    if (toolName == 'scrcpy') '/usr/local/bin/scrcpy',
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
