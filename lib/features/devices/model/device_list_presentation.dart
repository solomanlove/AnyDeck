import '../../../core/providers/modules/registered_device_model.dart';

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
}
