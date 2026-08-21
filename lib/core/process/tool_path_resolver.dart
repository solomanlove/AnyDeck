import 'dart:io';

/// 优先解析常见 Android 工具路径，找不到时回退到 PATH。
String resolveToolPath(String toolName) {
  final sdkRoot =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

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
