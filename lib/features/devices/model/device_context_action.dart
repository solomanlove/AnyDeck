import '../../../core/providers/modules/registered_device_model.dart';

/// 设备右键菜单动作与平台能力；不创建连接或执行设备命令。
enum DeviceContextAction {
  screenshot('screenshot'),
  mirror('screenMirror'),
  overview('deviceInfo', toolSlug: 'overview'),
  apps('apps', toolSlug: 'apps'),
  files('files', toolSlug: 'files'),
  terminal('terminal', toolSlug: 'terminal'),
  edit('editDeviceInfo');

  const DeviceContextAction(this.labelKey, {this.toolSlug});

  final String labelKey;
  final String? toolSlug;

  /// 纯 AirPlay 行没有 go-ios UDID，只提供已有投屏窗口入口。
  bool isVisibleFor(RegisteredDevice device) {
    if (device.id.startsWith('airplay-')) return this == mirror;
    return this != terminal || !device.isIos;
  }

  /// iOS 的 AirPlay LIVE 不代表 go-ios 在线，设备命令必须有真实连接。
  bool isEnabledFor(RegisteredDevice device, {bool hasAirPlaySession = false}) {
    if (!isVisibleFor(device)) return false;
    final connected =
        device.isOnline &&
        (!device.isIos || device.iosConnectionTypes.isNotEmpty);
    return switch (this) {
      overview || edit => true,
      mirror =>
        hasAirPlaySession ||
            (connected && (!device.isIos || device.hasUsbConnection)),
      _ => connected,
    };
  }
}
