import '../../../core/providers/modules/registered_device_model.dart';

/// 当前设备可用的连接通道；文案键供列表、设备墙和读屏说明共用。
enum DeviceConnectionKind {
  usb('deviceWorkspaceUsbConnected', 'deviceWorkspaceUsb'),
  tcp('connectionTcp', 'deviceWorkspaceTcp'),
  wireless('connectionWirelessDebug', 'deviceWorkspaceWifi'),
  iosNetwork('connectionIosNetwork', 'deviceWorkspaceWifi'),
  airplay('deviceWorkspaceAirplay', 'deviceWorkspaceAirplayConnection');

  const DeviceConnectionKind(this.fullLabelKey, this.shortLabelKey);

  /// Tooltip 和读屏使用的完整连接说明。
  final String fullLabelKey;

  /// 紧凑连接列使用的短名称。
  final String shortLabelKey;
}

/// 设备列表的名称、搜索与状态表达，复用本地概览数据，不启动设备探测。
class DeviceListPresentation {
  static String name(RegisteredDevice device, String? overviewName) {
    final custom = device.customName?.trim() ?? '';
    if (custom.isNotEmpty) return custom;
    final marketing = overviewName?.trim() ?? '';
    if (marketing.isNotEmpty && marketing != '-' && marketing != device.id) {
      return marketing;
    }
    return device.displayName;
  }

  static bool matches(
    RegisteredDevice device,
    String name,
    String query,
    bool onlineOnly,
  ) {
    if (onlineOnly && !device.isOnline) return false;
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        [
          name,
          device.id,
          device.model,
          device.serial,
          device.wifiIp,
          device.remark,
          ...device.tags,
          ...device.connections,
        ].whereType<String>().any(
          (value) => value.toLowerCase().contains(needle),
        );
  }

  static String statusKey(RegisteredDevice device) {
    if (device.isOnline) return 'deviceOnline';
    return switch (device.status) {
      'unauthorized' => 'deviceUnauthorizedLabel',
      'offline' => 'deviceOffline',
      _ => 'deviceUnavailableLabel',
    };
  }

  /// 返回全部真实在线通道，不把离线历史地址当成当前连接。
  ///
  /// iOS 依据发现的物理通道，Harmony 的 HDC 网络连接统一归为 TCP；
  /// 共享设备仅表示 TCP Bridge，AirPlay 会话则独立于设备调试在线状态。
  static List<DeviceConnectionKind> connections(
    RegisteredDevice device, {
    bool isAirplayMirroring = false,
  }) {
    final result = <DeviceConnectionKind>[];
    if (device.isOnline) {
      if (device.isShared) {
        result.add(DeviceConnectionKind.tcp);
      } else if (device.isIos) {
        if (device.hasUsbConnection) result.add(DeviceConnectionKind.usb);
        if (device.hasIosNetworkConnection) {
          result.add(DeviceConnectionKind.iosNetwork);
        }
      } else {
        if (device.hasUsbConnection) result.add(DeviceConnectionKind.usb);
        if (device.hasTcpConnection) result.add(DeviceConnectionKind.tcp);
        if (!device.isHarmony && device.hasWifiDebuggingConnection) {
          result.add(DeviceConnectionKind.wireless);
        }
      }
    }
    if (isAirplayMirroring) result.add(DeviceConnectionKind.airplay);
    return result;
  }
}
