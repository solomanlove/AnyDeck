import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

/// 设备控制命令集合，将 UI 操作映射到 adb shell 调用。
class DeviceActionService {
  DeviceActionService(this._adb);

  final AdbService _adb;

  /// 连接 adb TCP/IP 地址，例如 `192.168.1.10:5555`。
  Future<AdbResult> connect(String address) {
    return _adb.run(['connect', address]);
  }

  /// 断开 adb TCP/IP 地址连接。
  Future<AdbResult> disconnect(String address) {
    return _adb.run(['disconnect', address]);
  }

  /// 通过 Android input 命令输入文本，空格需要替换为 `%s`。
  Future<AdbResult> inputText(String deviceId, String text) {
    final escaped = text.trim().replaceAll(' ', '%s');
    return _adb.shellArgs(deviceId, ['input', 'text', escaped]);
  }

  /// 开关 Android 调试布局边界覆盖层。
  Future<AdbResult> toggleLayoutBounds(String deviceId, bool enabled) async {
    final flag = enabled ? '1' : '0';
    final propertyValue = enabled ? 'true' : 'false';
    final commands = [
      // AOSP 会读取 debug.layout 系统属性。
      ['setprop', 'debug.layout', propertyValue],
      // 部分 ROM 将开发者选项暴露为 settings key。
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

  /// 模拟电源键，用于亮屏或熄屏。
  Future<AdbResult> standby(String deviceId) {
    return _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_POWER']);
  }

  /// 通过 cmd uimode 切换系统夜间模式。
  Future<AdbResult> setDarkMode(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'cmd',
      'uimode',
      'night',
      enabled ? 'yes' : 'no',
    ]);
  }

  /// 通过 svc 开关 Wi-Fi。
  Future<AdbResult> setWifi(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'svc',
      'wifi',
      enabled ? 'enable' : 'disable',
    ]);
  }

  /// 通过 svc 开关移动数据。
  Future<AdbResult> setMobileData(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'svc',
      'data',
      enabled ? 'enable' : 'disable',
    ]);
  }

  /// 向选中设备发送 Android key code。
  Future<AdbResult> keyEvent(String deviceId, int keyCode) {
    return _adb.shellArgs(deviceId, ['input', 'keyevent', keyCode.toString()]);
  }

  /// 通过 Android 具名 key code 调高当前音频流音量。
  Future<AdbResult> volumeUp(String deviceId) {
    return _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_VOLUME_UP']);
  }

  /// 通过 Android 具名 key code 调低当前音频流音量。
  Future<AdbResult> volumeDown(String deviceId) {
    return _adb.shellArgs(deviceId, [
      'input',
      'keyevent',
      'KEYCODE_VOLUME_DOWN',
    ]);
  }

  /// 模拟菜单键。
  Future<AdbResult> menuKey(String deviceId) {
    return _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_MENU']);
  }

  /// 展开通知栏（下拉状态栏）。
  Future<AdbResult> openNotificationBar(String deviceId) {
    return _adb.shellArgs(deviceId, [
      'cmd',
      'statusbar',
      'expand-notifications',
    ]);
  }

  /// 切换屏幕自动旋转。
  Future<AdbResult> setAutoRotate(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'settings',
      'put',
      'system',
      'accelerometer_rotation',
      enabled ? '1' : '0',
    ]);
  }

  /// 在设备坐标上执行一次点击。
  Future<AdbResult> tap(String deviceId, int x, int y) {
    return _adb.shellArgs(deviceId, ['input', 'tap', '$x', '$y']);
  }

  /// 在两个设备坐标之间执行滑动手势。
  Future<AdbResult> swipe(
    String deviceId,
    int startX,
    int startY,
    int endX,
    int endY,
  ) {
    return _adb.shellArgs(deviceId, [
      'input',
      'swipe',
      '$startX',
      '$startY',
      '$endX',
      '$endY',
    ]);
  }

  /// 从 secure settings 读取设备 Android ID。
  Future<AdbResult> androidId(String deviceId) {
    return _adb.shellArgs(deviceId, [
      'settings',
      'get',
      'secure',
      'android_id',
    ]);
  }

  /// 读取用户可见的 Android 版本。
  Future<AdbResult> systemVersion(String deviceId) {
    return _adb.shellArgs(deviceId, ['getprop', 'ro.build.version.release']);
  }

  /// 读取当前焦点窗口，便于 UI 调试。
  Future<AdbResult> currentFocus(String deviceId) {
    return _adb.shell(deviceId, 'dumpsys window | grep mCurrentFocus');
  }

  /// 重启选中设备。
  Future<AdbResult> reboot(String deviceId) {
    return _adb.run(['-s', deviceId, 'reboot']);
  }

  /// setprop/settings 写入后通知 ActivityManager 重新加载系统属性。
  Future<void> _refreshSystemProperties(String deviceId) async {
    await _adb.shellArgs(deviceId, [
      'service',
      'call',
      'activity',
      '1599295570',
    ]);
  }
}
