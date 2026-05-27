import '../adb/adb_result.dart';
import '../adb/adb_service.dart';

class DeviceActionService {
  DeviceActionService(this._adb);

  final AdbService _adb;

  Future<AdbResult> connect(String address) {
    return _adb.run(['connect', address]);
  }

  Future<AdbResult> disconnect(String address) {
    return _adb.run(['disconnect', address]);
  }

  Future<AdbResult> inputText(String deviceId, String text) {
    final escaped = text.trim().replaceAll(' ', '%s');
    return _adb.shellArgs(deviceId, ['input', 'text', escaped]);
  }

  Future<AdbResult> toggleLayoutBounds(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'setprop',
      'debug.layout',
      enabled ? 'true' : 'false',
    ]);
  }

  Future<AdbResult> standby(String deviceId) {
    return _adb.shellArgs(deviceId, ['input', 'keyevent', 'KEYCODE_POWER']);
  }

  Future<AdbResult> setDarkMode(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'cmd',
      'uimode',
      'night',
      enabled ? 'yes' : 'no',
    ]);
  }

  Future<AdbResult> setWifi(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'svc',
      'wifi',
      enabled ? 'enable' : 'disable',
    ]);
  }

  Future<AdbResult> setMobileData(String deviceId, bool enabled) {
    return _adb.shellArgs(deviceId, [
      'svc',
      'data',
      enabled ? 'enable' : 'disable',
    ]);
  }

  Future<AdbResult> keyEvent(String deviceId, int keyCode) {
    return _adb.shellArgs(deviceId, ['input', 'keyevent', keyCode.toString()]);
  }

  Future<AdbResult> tap(String deviceId, int x, int y) {
    return _adb.shellArgs(deviceId, ['input', 'tap', '$x', '$y']);
  }

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

  Future<AdbResult> androidId(String deviceId) {
    return _adb.shellArgs(deviceId, [
      'settings',
      'get',
      'secure',
      'android_id',
    ]);
  }

  Future<AdbResult> systemVersion(String deviceId) {
    return _adb.shellArgs(deviceId, ['getprop', 'ro.build.version.release']);
  }

  Future<AdbResult> currentFocus(String deviceId) {
    return _adb.shell(deviceId, 'dumpsys window | grep mCurrentFocus');
  }

  Future<AdbResult> reboot(String deviceId) {
    return _adb.run(['-s', deviceId, 'reboot']);
  }
}
