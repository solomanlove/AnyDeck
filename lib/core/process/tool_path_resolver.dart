import 'dart:io';

String resolveToolPath(String toolName) {
  final sdkRoot =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  final home = Platform.environment['HOME'];

  final candidates = <String>[
    if (toolName == 'adb' && sdkRoot != null) '$sdkRoot/platform-tools/adb',
    if (toolName == 'adb' && home != null)
      '$home/Library/Android/sdk/platform-tools/adb',
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
