/// 设备概览面板展示的只读聚合信息。
class DeviceOverview {
  const DeviceOverview({
    required this.name,
    required this.brand,
    required this.model,
    required this.serial,
    required this.androidVersion,
    required this.kernelVersion,
    required this.processor,
    required this.storage,
    required this.memory,
    required this.physicalResolution,
    required this.resolution,
    required this.fontScale,
    required this.wifi,
    required this.ipAddress,
    required this.macAddress,
  });

  final String name;
  final String brand;
  final String model;
  final String serial;
  final String androidVersion;
  final String kernelVersion;
  final String processor;
  final String storage;
  final String memory;
  final String physicalResolution;
  final String resolution;
  final String fontScale;
  final String wifi;
  final String ipAddress;
  final String macAddress;
}
