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
    required this.logicalDensity,
    required this.refreshRate,
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
  final String logicalDensity;
  final String refreshRate;
  final String fontScale;
  final String wifi;
  final String ipAddress;
  final String macAddress;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'brand': brand,
      'model': model,
      'serial': serial,
      'androidVersion': androidVersion,
      'kernelVersion': kernelVersion,
      'processor': processor,
      'storage': storage,
      'memory': memory,
      'physicalResolution': physicalResolution,
      'resolution': resolution,
      'logicalDensity': logicalDensity,
      'refreshRate': refreshRate,
      'fontScale': fontScale,
      'wifi': wifi,
      'ipAddress': ipAddress,
      'macAddress': macAddress,
    };
  }

  factory DeviceOverview.fromJson(Map<String, dynamic> json) {
    return DeviceOverview(
      name: json['name'] as String? ?? '-',
      brand: json['brand'] as String? ?? '-',
      model: json['model'] as String? ?? '-',
      serial: json['serial'] as String? ?? '-',
      androidVersion: json['androidVersion'] as String? ?? '-',
      kernelVersion: json['kernelVersion'] as String? ?? '-',
      processor: json['processor'] as String? ?? '-',
      storage: json['storage'] as String? ?? '-',
      memory: json['memory'] as String? ?? '-',
      physicalResolution: json['physicalResolution'] as String? ?? '-',
      resolution: json['resolution'] as String? ?? '-',
      logicalDensity: json['logicalDensity'] as String? ?? '-',
      refreshRate: json['refreshRate'] as String? ?? '-',
      fontScale: json['fontScale'] as String? ?? '-',
      wifi: json['wifi'] as String? ?? '-',
      ipAddress: json['ipAddress'] as String? ?? '-',
      macAddress: json['macAddress'] as String? ?? '-',
    );
  }

  DeviceOverview copyWith({
    String? name,
    String? brand,
    String? model,
    String? serial,
    String? androidVersion,
    String? kernelVersion,
    String? processor,
    String? storage,
    String? memory,
    String? physicalResolution,
    String? resolution,
    String? logicalDensity,
    String? refreshRate,
    String? fontScale,
    String? wifi,
    String? ipAddress,
    String? macAddress,
  }) {
    return DeviceOverview(
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      serial: serial ?? this.serial,
      androidVersion: androidVersion ?? this.androidVersion,
      kernelVersion: kernelVersion ?? this.kernelVersion,
      processor: processor ?? this.processor,
      storage: storage ?? this.storage,
      memory: memory ?? this.memory,
      physicalResolution: physicalResolution ?? this.physicalResolution,
      resolution: resolution ?? this.resolution,
      logicalDensity: logicalDensity ?? this.logicalDensity,
      refreshRate: refreshRate ?? this.refreshRate,
      fontScale: fontScale ?? this.fontScale,
      wifi: wifi ?? this.wifi,
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
    );
  }
}
