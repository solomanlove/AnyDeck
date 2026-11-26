import '../../../app/l10n/app_localizations.dart';
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
  static const _emulatorTagKey = 'deviceEmulatorTag';
  static final _emulatorLabels = {
    for (final locale in AppLocalizations.supportedLocales)
      AppLocalizations(locale).t(_emulatorTagKey).toLowerCase(),
  };

  /// 自动标签与自定义标签共用同一字段，已有中英文模拟器标签时只显示一次。
  static String? automaticTag(RegisteredDevice device, AppLocalizations l10n) {
    if (!device.isEmulator) return null;
    final hasEmulatorTag = device.tags.any(
      (tag) => _emulatorLabels.contains(tag.trim().toLowerCase()),
    );
    return hasEmulatorTag ? null : l10n.t(_emulatorTagKey);
  }

  /// 设备列表、设备墙和编辑框使用相同的标签内容。
  static List<String> tags(RegisteredDevice device, AppLocalizations l10n) {
    final tag = automaticTag(device, l10n);
    return tag == null ? device.tags : [tag, ...device.tags];
  }

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
    bool onlineOnly, {
    required AppLocalizations l10n,
  }) {
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
          ...tags(device, l10n),
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
