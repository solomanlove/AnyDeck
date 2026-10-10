import '../../core/providers/modules/registered_device_model.dart';

/// AirPlay 无法提供 USB UDID；优先关联唯一的在线 USB iOS 设备以复用其投屏窗口。
RegisteredDevice? resolveAirPlayMirrorTarget(
  Iterable<RegisteredDevice> devices,
) {
  final onlineIos = devices
      .where((device) => device.isIos && device.isOnline)
      .toList();
  return onlineIos.where((device) => device.hasUsbConnection).firstOrNull ??
      onlineIos.firstOrNull;
}
