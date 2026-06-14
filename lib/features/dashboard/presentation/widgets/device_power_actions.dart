import '../../../../core/adb/adb_result.dart';
import '../../../../core/device_actions/device_action_service.dart';
import '../../../../core/providers/app_providers.dart';

/// 电源键会改变设备物理屏幕状态，成功后需要同步清理投屏侧的关闭屏幕标记。
Future<AdbResult> pressPowerKeyAndResetScreenPower({
  required DeviceActionService actions,
  required String deviceId,
  required ScreenPowerOffNotifier screenPowerOffNotifier,
}) async {
  final result = await actions.standby(deviceId);
  if (result.isSuccess) {
    screenPowerOffNotifier.setOff(false);
  }
  return result;
}
