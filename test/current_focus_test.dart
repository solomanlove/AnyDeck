import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_actions/device_action_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 前台窗口只输出可复制的组件名，并只向所选设备查询一次。
void main() {
  test('同一份输出里先出现 null 时仍提取当前 Activity', () async {
    final result = await _query(
      const AdbResult(
        exitCode: 0,
        stdout:
            'mCurrentFocus=null\r\n'
            '  mCurrentFocus=Window{bf9e707 u0 '
            'com.ubrmb.app/com.ubrmb.app.ui.MainActivity}\r\n',
        stderr: '',
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(result.stdout, 'com.ubrmb.app/com.ubrmb.app.ui.MainActivity');
  });

  test('多个窗口按出现顺序展示，补全简写类名后去重并保留内部类名', () async {
    final result = await _query(
      const AdbResult(
        exitCode: 0,
        stdout: r'''
    mCurrentFocus=Window{aa u0 com.example/.MainActivity}
    mCurrentFocus=Window{bb u0 NotificationShade}
    mCurrentFocus=Window{cc u10 com.android.settings/.Settings$WifiSettingsActivity}
    mCurrentFocus=Window{dd u0 com.example/com.example.MainActivity}
''',
        stderr: '',
      ),
    );
    expect(
      result.stdout,
      'com.example/com.example.MainActivity\n'
      r'com.android.settings/com.android.settings.Settings$WifiSettingsActivity',
    );
  });

  test('只有空焦点和系统窗口时返回空内容', () async {
    final result = await _query(
      const AdbResult(
        exitCode: 0,
        stdout: 'mCurrentFocus=null\nmCurrentFocus=Window{aa u0 StatusBar}',
        stderr: '',
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(result.stdout, isEmpty);
  });

  test('ADB 查询失败时保留退出码和断连信息', () async {
    const failure = AdbResult(
      exitCode: 1,
      stdout: '',
      stderr: "adb: device 'device1' not found",
    );
    final result = await _query(failure);
    expect(result.exitCode, failure.exitCode);
    expect(result.stdout, failure.stdout);
    expect(result.stderr, failure.stderr);
    expect(result.disconnectedDeviceId, 'device1');
  });
}

Future<AdbResult> _query(AdbResult response) async {
  final adb = _FocusAdbService(response);
  final result = await DeviceActionService(adb).currentFocus('device1');
  expect(adb.commands, ['dumpsys window | grep mCurrentFocus']);
  return result;
}

/// 记录 shell 查询，避免额外读取 Activity 或 Fragment 信息。
class _FocusAdbService extends AdbService {
  _FocusAdbService(this.response);

  final AdbResult response;
  final commands = <String>[];

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    expect(deviceId, 'device1');
    commands.add(command);
    return response;
  }
}
