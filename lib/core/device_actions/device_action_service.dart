import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

typedef DeviceSdkVersionResolver = int? Function(String deviceId);

/// 设备控制命令集合，将 UI 操作映射到 adb shell 调用。
class DeviceActionService {
  DeviceActionService(
    this._adb, {
    DeviceSdkVersionResolver? sdkVersionResolver,
  }) : _sdkVersionResolver = sdkVersionResolver;

  static const int _streamMusic = 3;
  static const int _fallbackMaxMediaVolume = 15;
  static const List<int> _audioServiceSetStreamVolumeCodes = [
    4,
    5,
    6,
    7,
    8,
    9,
    10,
  ];

  final AdbService _adb;
  final DeviceSdkVersionResolver? _sdkVersionResolver;

  /// 连接 adb TCP/IP 地址，例如 `192.168.1.10:5555`。
  Future<AdbResult> connect(String address) => _adb.run(['connect', address]);

  /// 断开 adb TCP/IP 地址连接。
  Future<AdbResult> disconnect(String address) =>
      _adb.run(['disconnect', address]);

  /// 通过 Android input 命令输入文本，空格需要替换为 `%s`。
  Future<AdbResult> inputText(String deviceId, String text) {
    // 1. 转义 Android shell 中的特殊控制字符，防止命令注入与解析错误
    final escapedShell = text.replaceAllMapped(
      RegExp(r'''([`;$&|<>*?#()\[\]{}\\!~'"\u0000])'''),
      (match) => '\\${match.group(1)}',
    );
    // 2. 替换空格为 input text 所支持的 %s 标识符
    final escaped = escapedShell.trim().replaceAll(' ', '%s');
    return _adb.shellArgs(deviceId, ['input', 'text', escaped]);
  }

  /// 开关 Android 调试布局边界覆盖层。
  Future<AdbResult> toggleLayoutBounds(String deviceId, bool enabled) async {
    final flag = enabled ? '1' : '0';
    final propertyValue = enabled ? 'true' : 'false';
    final commands = [
      ['setprop', 'debug.layout', propertyValue],
      ['settings', 'put', 'global', 'debug_layout', flag],
      ['settings', 'put', 'system', 'debug_layout', flag],
    ];

    AdbResult? lastResult;
    for (final command in commands) {
      lastResult = await _adb.shellArgs(deviceId, command);
      if (lastResult.isSuccess) {
        await _refreshSystemProperties(deviceId);
        return lastResult;
      }
    }
    return lastResult ?? const AdbResult(exitCode: 1, stdout: '', stderr: '');
  }

  /// 开关 Android 调试点按操作反馈 (Show taps)。
  Future<AdbResult> setShowTouches(String deviceId, bool enabled) {
    final flag = enabled ? '1' : '0';
    return _adb.shellArgs(deviceId, [
      'settings',
      'put',
      'system',
      'show_touches',
      flag,
    ]);
  }

  /// 开关 Android 指针位置 (Pointer location)。
  Future<AdbResult> setPointerLocation(String deviceId, bool enabled) {
    final flag = enabled ? '1' : '0';
    return _adb.shellArgs(deviceId, [
      'settings',
      'put',
      'system',
      'pointer_location',
      flag,
    ]);
  }

  /// 开关 Android 演示模式 (Demo mode)。
  Future<AdbResult> setDemoMode(String deviceId, bool enabled) async {
    final flag = enabled ? '1' : '0';
    await _adb.shellArgs(deviceId, [
      'settings',
      'put',
      'global',
      'sysui_demo_allowed',
      flag,
    ]);
    final action = enabled ? 'enter' : 'exit';
    return _adb.shellArgs(deviceId, [
      'am',
      'broadcast',
      '-a',
      'com.android.systemui.demo',
      '-e',
      'command',
      action,
    ]);
  }

  /// 模拟电源键，用于亮屏或熄屏。
  Future<AdbResult> standby(String deviceId) =>
      _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_POWER']);

  /// 通过 cmd uimode 切换系统夜间模式。
  Future<AdbResult> setDarkMode(String deviceId, bool enabled) => _adb
      .shellArgs(deviceId, ['cmd', 'uimode', 'night', enabled ? 'yes' : 'no']);

  /// 通过 svc 开关 Wi-Fi。
  Future<AdbResult> setWifi(String deviceId, bool enabled) =>
      _adb.shellArgs(deviceId, ['svc', 'wifi', enabled ? 'enable' : 'disable']);

  /// 通过 svc 开关移动数据。
  Future<AdbResult> setMobileData(String deviceId, bool enabled) =>
      _adb.shellArgs(deviceId, ['svc', 'data', enabled ? 'enable' : 'disable']);

  /// 优先使用 cmd connectivity 开关离线模式（飞行模式），失败时回退到广播方式以保障最大兼容性。
  Future<AdbResult> setAirplaneMode(String deviceId, bool enabled) async {
    final result = await _adb.shellArgs(deviceId, [
      'cmd',
      'connectivity',
      'airplane-mode',
      enabled ? 'enable' : 'disable',
    ]);
    if (!result.isSuccess) {
      final value = enabled ? '1' : '0';
      await _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'global',
        'airplane_mode_on',
        value,
      ]);
      return _adb.shellArgs(deviceId, [
        'am',
        'broadcast',
        '-a',
        'android.intent.action.AIRPLANE_MODE',
        '--ez',
        'state',
        enabled ? 'true' : 'false',
      ]);
    }
    return result;
  }

  /// 安全地开关 TalkBack 辅助服务，同时保留其他启用的辅助服务。
  Future<AdbResult> setTalkback(String deviceId, bool enabled) async {
    final getRes = await _adb.shellArgs(deviceId, [
      'settings',
      'get',
      'secure',
      'enabled_accessibility_services',
    ]);
    String services = getRes.stdout.trim();
    if (services == 'null' || services == 'Setting not found') {
      services = '';
    }
    const talkbackService =
        'com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService';
    final serviceList = services
        .split(':')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (enabled) {
      if (!serviceList.contains(talkbackService)) {
        serviceList.add(talkbackService);
      }
    } else {
      serviceList.remove(talkbackService);
      serviceList.removeWhere((s) => s.contains('talkback'));
    }
    final newServices = serviceList.join(':');

    if (newServices.isEmpty) {
      await _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'secure',
        'enabled_accessibility_services',
        '""',
      ]);
    } else {
      await _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'secure',
        'enabled_accessibility_services',
        newServices,
      ]);
    }

    return _adb.shellArgs(deviceId, [
      'settings',
      'put',
      'secure',
      'accessibility_enabled',
      enabled ? '1' : '0',
    ]);
  }

  /// 向选中设备发送 Android key code。
  Future<AdbResult> keyEvent(String deviceId, int keyCode) =>
      _adb.shellArgs(deviceId, ['input', 'keyevent', keyCode.toString()]);

  /// 通过 Android 具名 key code 调高当前音频流音量。
  Future<AdbResult> volumeUp(String deviceId) =>
      _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_VOLUME_UP']);

  /// 通过 Android 具名 key code 调低当前音频流音量。
  Future<AdbResult> volumeDown(String deviceId) =>
      _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_VOLUME_DOWN']);

  /// 将手机主要音频流设为最大，并退出静音模式。
  Future<AdbResult> volumeMax(String deviceId) async {
    final ringerResult = await _adb.shellArgs(deviceId, [
      'cmd',
      'audio',
      'set-ringer-mode',
      'NORMAL',
    ]);
    final volumeResult = await _setMediaVolumeToBoundary(
      deviceId,
      useMax: true,
    );
    if (volumeResult.isSuccess) {
      return volumeResult;
    }
    if (!ringerResult.isSuccess) {
      return ringerResult;
    }
    return _fallbackVolumeMax(deviceId);
  }

  /// 将手机主要音频流设为静音，并进入系统静音模式。
  Future<AdbResult> volumeMute(String deviceId) async {
    final volumeResult = await _setMediaVolumeToBoundary(
      deviceId,
      useMax: false,
    );
    final ringerResult = await _adb.shellArgs(deviceId, [
      'cmd',
      'audio',
      'set-ringer-mode',
      'SILENT',
    ]);
    if (volumeResult.isSuccess) {
      return volumeResult;
    }
    final fallbackResult = await _fallbackVolumeMute(deviceId);
    if (fallbackResult.isSuccess) {
      return fallbackResult;
    }
    if (ringerResult.isSuccess) {
      return ringerResult;
    }
    return volumeResult;
  }

  /// 根据 Android SDK 选择底层音量命令，长按音量键只控制媒体流。
  Future<AdbResult> _setMediaVolumeToBoundary(
    String deviceId, {
    required bool useMax,
  }) async {
    final sdkVersion = await _resolveSdkVersion(deviceId);
    if (sdkVersion != null && sdkVersion >= 30) {
      return _setMediaSessionVolume(deviceId, useMax: useMax);
    }
    if (sdkVersion != null && sdkVersion >= 26) {
      return _setMediaCommandVolume(deviceId, useMax: useMax);
    }
    if (sdkVersion != null) {
      return _setAudioServiceCallVolume(deviceId, useMax: useMax);
    }

    final modernResult = await _setMediaSessionVolume(deviceId, useMax: useMax);
    if (modernResult.isSuccess) return modernResult;
    final mediaResult = await _setMediaCommandVolume(deviceId, useMax: useMax);
    if (mediaResult.isSuccess) return mediaResult;
    return _setAudioServiceCallVolume(deviceId, useMax: useMax);
  }

  Future<int?> _resolveSdkVersion(String deviceId) async {
    final cachedSdk = _sdkVersionResolver?.call(deviceId);
    if (cachedSdk != null && cachedSdk > 0) {
      return cachedSdk;
    }

    final result = await _adb.shellArgs(deviceId, [
      'getprop',
      'ro.build.version.sdk',
    ]);
    if (!result.isSuccess) return null;
    final sdk = int.tryParse(result.stdout.trim());
    return sdk != null && sdk > 0 ? sdk : null;
  }

  Future<AdbResult> _setMediaSessionVolume(
    String deviceId, {
    required bool useMax,
  }) async {
    final target = useMax
        ? await _readMediaSessionMaxVolume(deviceId)
        : 0;
    return _adb.shellArgs(deviceId, [
      'cmd',
      'media_session',
      'volume',
      '--stream',
      '$_streamMusic',
      '--set',
      '$target',
    ]);
  }

  Future<int> _readMediaSessionMaxVolume(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, [
      'cmd',
      'media_session',
      'volume',
      '--stream',
      '$_streamMusic',
      '--get',
    ]);
    return _parseMaxVolume(result.stdout) ?? _fallbackMaxMediaVolume;
  }

  Future<AdbResult> _setMediaCommandVolume(
    String deviceId, {
    required bool useMax,
  }) async {
    final target = useMax ? await _readMediaCommandMaxVolume(deviceId) : 0;
    return _adb.shellArgs(deviceId, [
      'media',
      'volume',
      '--stream',
      '$_streamMusic',
      '--set',
      '$target',
    ]);
  }

  Future<int> _readMediaCommandMaxVolume(String deviceId) async {
    final result = await _adb.shellArgs(deviceId, [
      'media',
      'volume',
      '--stream',
      '$_streamMusic',
      '--get',
    ]);
    return _parseMaxVolume(result.stdout) ?? _fallbackMaxMediaVolume;
  }

  Future<AdbResult> _setAudioServiceCallVolume(
    String deviceId, {
    required bool useMax,
  }) async {
    final target = useMax ? _fallbackMaxMediaVolume : 0;
    final failedMessages = <String>[];
    for (final code in _audioServiceSetStreamVolumeCodes) {
      final result = await _adb.shellArgs(deviceId, [
        'service',
        'call',
        'audio',
        '$code',
        'i32',
        '$_streamMusic',
        'i32',
        '$target',
        'i32',
        '0',
      ]);
      if (_isAudioCommandSuccess(result)) {
        return result;
      }
      failedMessages.add('service call audio $code: ${result.message}');
    }

    return AdbResult(
      exitCode: 1,
      stdout: '',
      stderr: failedMessages.isEmpty ? '音量设置失败' : failedMessages.join('\n'),
    );
  }

  int? _parseMaxVolume(String output) {
    final rangeMatch = RegExp(
      r'\[\s*(-?\d+)\s*\.\.\s*(-?\d+)\s*\]',
    ).firstMatch(output);
    if (rangeMatch != null) {
      return int.tryParse(rangeMatch.group(2) ?? '');
    }

    final values = RegExp(r'-?\d+')
        .allMatches(output)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    if (values.isEmpty) return null;
    values.sort();
    return values.last;
  }

  bool _isAudioCommandSuccess(AdbResult result) {
    if (!result.isSuccess) return false;
    final message = '${result.stdout}\n${result.stderr}'.toLowerCase();
    return !message.contains('exception') &&
        !message.contains('unknown') &&
        !message.contains('not found') &&
        !message.contains('invalid');
  }

  Future<AdbResult> _fallbackVolumeMax(String deviceId) async {
    AdbResult? lastResult;
    for (var i = 0; i < 30; i += 1) {
      lastResult = await volumeUp(deviceId);
      if (!lastResult.isSuccess) {
        return lastResult;
      }
    }
    return lastResult ?? const AdbResult(exitCode: 1, stdout: '', stderr: '');
  }

  Future<AdbResult> _fallbackVolumeMute(String deviceId) async {
    AdbResult? lastResult;
    for (var i = 0; i < 30; i += 1) {
      lastResult = await volumeDown(deviceId);
      if (!lastResult.isSuccess) {
        return lastResult;
      }
    }
    return lastResult ?? const AdbResult(exitCode: 1, stdout: '', stderr: '');
  }

  /// 模拟菜单键。
  Future<AdbResult> menuKey(String deviceId) =>
      _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_MENU']);

  /// 展开通知栏（下拉状态栏）。
  Future<AdbResult> openNotificationBar(String deviceId) =>
      _adb.shellArgs(deviceId, ['cmd', 'statusbar', 'expand-notifications']);

  /// 切换屏幕自动旋转。
  Future<AdbResult> setAutoRotate(String deviceId, bool enabled) =>
      _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'system',
        'accelerometer_rotation',
        enabled ? '1' : '0',
      ]);

  /// 在设备坐标上执行一次点击。
  Future<AdbResult> tap(String deviceId, int x, int y) =>
      _adb.shellArgs(deviceId, ['input', 'tap', '$x', '$y']);

  /// 在两个设备坐标之间执行滑动手势。
  Future<AdbResult> swipe(
    String deviceId,
    int startX,
    int startY,
    int endX,
    int endY,
  ) => _adb.shellArgs(deviceId, [
    'input',
    'swipe',
    '$startX',
    '$startY',
    '$endX',
    '$endY',
  ]);

  /// 从 secure settings 读取设备 Android ID。
  Future<AdbResult> androidId(String deviceId) =>
      _adb.shellArgs(deviceId, ['settings', 'get', 'secure', 'android_id']);

  /// 读取当前焦点窗口，并解析其中的 Fragment 类型信息。
  Future<AdbResult> currentFocus(String deviceId) async {
    final focusResult = await _adb.shell(
      deviceId,
      'dumpsys window | grep mCurrentFocus',
    );
    if (!focusResult.isSuccess || focusResult.stdout.trim().isEmpty) {
      return focusResult;
    }

    final focusLine = focusResult.stdout.trim();
    if (focusLine.contains('mCurrentFocus=null')) {
      return focusResult;
    }

    // 解析包名，例如从 mCurrentFocus=Window{2baae81 u0 com.xxxx.xxxx/com.xxxx.xxxx.ui.MainActivity} 中提取 com.xxxx.xxxx
    String packageName = '';
    final slashIndex = focusLine.indexOf('/');
    if (slashIndex != -1) {
      final openBraceIndex = focusLine.lastIndexOf('{', slashIndex);
      final startSearch = openBraceIndex != -1 ? openBraceIndex + 1 : 0;
      final prefix = focusLine.substring(startSearch, slashIndex);
      final parts = prefix.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        packageName = parts.last;
      }
    }

    if (packageName.isEmpty) {
      return focusResult;
    }

    // 获取该应用当前所有的 activity 和 fragment 状态
    final activityResult = await _adb.shell(
      deviceId,
      'dumpsys activity $packageName',
    );
    if (!activityResult.isSuccess || activityResult.stdout.trim().isEmpty) {
      return focusResult;
    }

    // 解析出 Added Fragments
    final fragments = _parseFragmentsFromDump(activityResult.stdout);
    if (fragments.isEmpty) {
      return focusResult;
    }

    final combinedStdout =
        '$focusLine\n\nActive Fragments:\n'
        '${fragments.map((f) => '  - $f').join('\n')}';

    return AdbResult(
      exitCode: focusResult.exitCode,
      stdout: combinedStdout,
      stderr: focusResult.stderr,
    );
  }

  /// 从 dumpsys activity 输出中解析活跃的 Fragment 列表（按层级从底至顶）。
  List<String> _parseFragmentsFromDump(String dumpsysOutput) {
    final fragments = <String>[];
    final lines = dumpsysOutput.split('\n');
    int flag = 0;

    for (int i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.contains('#') && flag == 0) {
        flag = 1;
      } else if (line.startsWith('Added Fragments:')) {
        flag = 2;
      }

      if (flag == 1 && line.startsWith('#')) {
        final afterHash = line.substring(1).trimLeft();
        if (afterHash.isNotEmpty && _isDigit(afterHash[0])) {
          final indexOfSpace = line.indexOf(' ');
          if (indexOfSpace != -1) {
            String fragmentName = line.substring(indexOfSpace + 1).trim();
            if (fragmentName.contains('{')) {
              fragmentName = fragmentName.split('{').first.trim();
            }
            if (fragmentName.isNotEmpty &&
                !fragments.contains(fragmentName) &&
                fragmentName != 'ReportFragment' &&
                fragmentName != 'SupportRequestManagerFragment' &&
                fragmentName != 'AutofillManager') {
              fragments.add(fragmentName);
            }
          }
        }
      }
    }
    return fragments;
  }

  bool _isDigit(String char) =>
      char.isNotEmpty && char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;

  /// 重启选中设备，支持可选模式 (如 recovery, bootloader, sideload, sideload-auto-reboot)。
  Future<AdbResult> reboot(String deviceId, [String? mode]) => _adb.run([
    '-s',
    deviceId,
    'reboot',
    if (mode != null && mode.trim().isNotEmpty) mode.trim(),
  ]);

  /// 打开开发者选项。
  Future<AdbResult> openDeveloperSettings(String deviceId) => _adb.shellArgs(
    deviceId,
    ['am', 'start', '-a', 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS'],
  );

  /// 打开手机信息。
  Future<AdbResult> openDeviceInfoSettings(String deviceId) => _adb.shellArgs(
    deviceId,
    ['am', 'start', '-a', 'android.settings.DEVICE_INFO_SETTINGS'],
  );

  /// 打开语言设置。
  Future<AdbResult> openLocaleSettings(String deviceId) => _adb.shellArgs(
    deviceId,
    ['am', 'start', '-a', 'android.settings.LOCALE_SETTINGS'],
  );

  /// 打开系统设置。
  Future<AdbResult> openMainSettings(String deviceId) => _adb.shellArgs(
    deviceId,
    ['am', 'start', '-a', 'android.settings.SETTINGS'],
  );

  /// 打开 Wi-Fi 设置。
  Future<AdbResult> openWifiSettings(String deviceId) => _adb.shellArgs(
    deviceId,
    ['am', 'start', '-a', 'android.settings.WIFI_SETTINGS'],
  );

  /// 打开应用管理。
  Future<AdbResult> openManageApplicationsSettings(String deviceId) =>
      _adb.shellArgs(deviceId, [
        'am',
        'start',
        '-a',
        'android.settings.MANAGE_APPLICATIONS_SETTINGS',
      ]);

  /// 打开自定义 Applink/Deeplink 链接。
  Future<AdbResult> openCustomDeeplink(String deviceId, String uri) {
    final escapedUri = uri.replaceAllMapped(
      RegExp(r'''([`;$&|<>*?#()\[\]{}\\!~'"])'''),
      (match) => '\\${match.group(1)}',
    );
    return _adb.shellArgs(deviceId, [
      'am',
      'start',
      '-a',
      'android.intent.action.VIEW',
      '-d',
      escapedUri,
    ]);
  }

  /// setprop/settings 写入后通知 ActivityManager 重新加载 system properties。
  Future<void> _refreshSystemProperties(String deviceId) =>
      _adb.shellArgs(deviceId, ['service', 'call', 'activity', '1599295570']);

  /// 设置系统字体缩放。
  Future<AdbResult> setFontScale(String deviceId, double scale) =>
      _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'system',
        'font_scale',
        scale.toString(),
      ]);

  /// 设置显示大小 (DPI)。
  Future<AdbResult> setDisplayDensity(String deviceId, int density) =>
      _adb.shellArgs(deviceId, ['wm', 'density', density.toString()]);

  /// 重置显示大小 (DPI) 为物理默认。
  Future<AdbResult> resetDisplayDensity(String deviceId) =>
      _adb.shellArgs(deviceId, ['wm', 'density', 'reset']);

  /// 设置窗口动画缩放。
  Future<AdbResult> setWindowAnimationScale(String deviceId, double scale) =>
      _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'global',
        'window_animation_scale',
        scale.toString(),
      ]);

  /// 设置过渡动画缩放。
  Future<AdbResult> setTransitionAnimationScale(
    String deviceId,
    double scale,
  ) => _adb.shellArgs(deviceId, [
    'settings',
    'put',
    'global',
    'transition_animation_scale',
    scale.toString(),
  ]);

  /// 设置动画程序时长缩放。
  Future<AdbResult> setAnimatorDurationScale(String deviceId, double scale) =>
      _adb.shellArgs(deviceId, [
        'settings',
        'put',
        'global',
        'animator_duration_scale',
        scale.toString(),
      ]);

  /// 设置显示分辨率大小，例如 "1080x1920"
  Future<AdbResult> setDisplaySize(String deviceId, String size) =>
      _adb.shellArgs(deviceId, ['wm', 'size', size]);

  /// 重置显示分辨率大小为默认物理值
  Future<AdbResult> resetDisplaySize(String deviceId) =>
      _adb.shellArgs(deviceId, ['wm', 'size', 'reset']);

  /// 设置 GPU/HWUI 渲染分析模式，支持 "visual_bars", "true", "false"
  Future<AdbResult> setHwuiProfile(String deviceId, String value) async {
    final result = await _adb.shellArgs(deviceId, [
      'setprop',
      'debug.hwui.profile',
      value,
    ]);
    if (result.isSuccess) await _refreshSystemProperties(deviceId);
    return result;
  }
}
