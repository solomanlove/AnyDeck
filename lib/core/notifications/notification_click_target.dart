import '../providers/modules/registered_device_model.dart';
import 'notification_database.dart';
import 'notification_device_identity.dart';

/// 点击通知时优先匹配硬件身份；无 Serial 时必须核验持久化安装来源，防止 IP 复用串机。
Future<RegisteredDevice?> resolveNotificationClickDevice({
  required List<RegisteredDevice> devices,
  required NotificationDatabase database,
  required String deviceId,
  String? deviceSerial,
  String? installationId,
  int? userId,
}) async {
  final hardwareId = notificationHardwareId(deviceSerial);
  if (hardwareId != null) {
    return findNotificationDevice(devices, deviceId, stableId: hardwareId);
  }
  // 旧版消息和连接通知没有安装来源，沿用 route 的兼容逻辑。
  if (installationId == null || userId == null) {
    return findNotificationDevice(devices, deviceId);
  }
  final source = await database.readSource(installationId, userId);
  final storedHardwareId = notificationHardwareId(source.identity?.stableId);
  if (storedHardwareId != null) {
    return findNotificationDevice(
      devices,
      deviceId,
      stableId: storedHardwareId,
    );
  }
  for (final device in devices) {
    final current = await database.resolveSource(device.serial ?? device.id);
    if (current?.installationId == installationId &&
        current?.androidUserId == userId) {
      return device;
    }
  }
  return null;
}
