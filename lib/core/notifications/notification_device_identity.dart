import '../providers/modules/registered_device_model.dart';

/// 消息来源的可持久化身份；名称只用于展示，stableId 不使用网络地址。
class NotificationDeviceIdentity {
  const NotificationDeviceIdentity({
    required this.stableId,
    required this.name,
  });

  final String stableId;
  final String name;

  /// 始终附带短标识；已知设备尾码冲突时延长，避免同型号手机混淆。
  String label(Iterable<String> knownIds) {
    if (stableId.isEmpty) return name;
    var length = stableId.length < 4 ? stableId.length : 4;
    while (length < stableId.length &&
        knownIds.any(
          (id) =>
              id != stableId &&
              id.endsWith(stableId.substring(stableId.length - length)),
        )) {
      length++;
    }
    return '$name · ${stableId.substring(stableId.length - length)}';
  }
}

/// 复用设备注册表的 Serial/连接映射，不为来源展示额外执行 ADB。
RegisteredDevice? findNotificationDevice(
  Iterable<RegisteredDevice> devices,
  String deviceId, {
  String? stableId,
}) {
  // 有稳定身份时禁止用旧 IP 命中另一台手机。
  if (stableId != null && !stableId.startsWith('installation:')) {
    for (final device in devices) {
      if (device.serial == stableId ||
          device.id == stableId ||
          device.connections.contains(stableId)) {
        return device;
      }
    }
    return null;
  }
  for (final device in devices) {
    if (device.id == deviceId ||
        device.serial == deviceId ||
        device.connections.contains(deviceId)) {
      return device;
    }
  }
  return null;
}

/// 网络 route 只参与寻址，身份未知时使用 Companion 安装实例兜底。
String? notificationHardwareId(String? value) {
  if (value == null ||
      value.trim().isEmpty ||
      value.contains(':') ||
      value.contains('.') ||
      value == 'unknown') {
    return null;
  }
  return value;
}

/// 通知与列表共享名称优先级：设备备注、有效型号、历史快照、本地化兜底。
NotificationDeviceIdentity resolveNotificationIdentity({
  required Iterable<RegisteredDevice> devices,
  required String deviceId,
  String? serial,
  required String installationId,
  required String fallbackName,
  NotificationDeviceIdentity? snapshot,
}) {
  final stableId = snapshot?.stableId ?? notificationHardwareId(serial);
  final device = findNotificationDevice(devices, deviceId, stableId: stableId);
  final hardwareId =
      notificationHardwareId(device?.serial) ??
      notificationHardwareId(snapshot?.stableId) ??
      notificationHardwareId(serial) ??
      notificationHardwareId(device?.id);
  final displayName = device?.displayName;
  return NotificationDeviceIdentity(
    stableId:
        hardwareId ?? snapshot?.stableId ??
        (installationId.isEmpty ? '' : 'installation:$installationId'),
    name: displayName != null && displayName != device?.id
        ? displayName
        : (snapshot?.name.isNotEmpty == true ? snapshot!.name : fallbackName),
  );
}

/// 同名设备的短标识冲突集合包含离线注册设备，断线不改变辨识规则。
Iterable<String> notificationKnownDeviceIds(
  Iterable<RegisteredDevice> devices,
) => devices
    .map(
      (d) => notificationHardwareId(d.serial) ?? notificationHardwareId(d.id),
    )
    .whereType<String>();
