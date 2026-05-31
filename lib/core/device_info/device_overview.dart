/// 设备概览面板展示的只读聚合信息。
class DeviceOverview {
  const DeviceOverview({
    required this.name,
    required this.brand,
    required this.model,
    required this.serial,
    required this.androidId,
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
    required this.wifiEnabled,
    required this.ipAddress,
    required this.macAddress,
    required this.airplaneModeEnabled,
    required this.mobileDataEnabled,
    required this.talkbackEnabled,
    required this.windowAnimationScale,
    required this.transitionAnimationScale,
    required this.animatorDurationScale,
    required this.rawResolution,
    required this.hwuiProfile,
    required this.showTouchesEnabled,
    required this.pointerLocationEnabled,
  });

  final String name;
  final String brand;
  final String model;
  final String serial;
  final String androidId;
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
  final bool wifiEnabled;
  final String ipAddress;
  final String macAddress;
  final bool airplaneModeEnabled;
  final bool mobileDataEnabled;
  final bool talkbackEnabled;
  final String windowAnimationScale;
  final String transitionAnimationScale;
  final String animatorDurationScale;
  final String rawResolution;
  final String hwuiProfile;
  final bool showTouchesEnabled;
  final bool pointerLocationEnabled;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'brand': brand,
      'model': model,
      'serial': serial,
      'androidId': androidId,
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
      'wifiEnabled': wifiEnabled,
      'ipAddress': ipAddress,
      'macAddress': macAddress,
      'airplaneModeEnabled': airplaneModeEnabled,
      'mobileDataEnabled': mobileDataEnabled,
      'talkbackEnabled': talkbackEnabled,
      'windowAnimationScale': windowAnimationScale,
      'transitionAnimationScale': transitionAnimationScale,
      'animatorDurationScale': animatorDurationScale,
      'rawResolution': rawResolution,
      'hwuiProfile': hwuiProfile,
      'showTouchesEnabled': showTouchesEnabled,
      'pointerLocationEnabled': pointerLocationEnabled,
    };
  }

  factory DeviceOverview.fromJson(Map<String, dynamic> json) {
    return DeviceOverview(
      name: json['name'] as String? ?? '-',
      brand: json['brand'] as String? ?? '-',
      model: json['model'] as String? ?? '-',
      serial: json['serial'] as String? ?? '-',
      androidId: json['androidId'] as String? ?? '-',
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
      wifiEnabled: json['wifiEnabled'] as bool? ?? false,
      ipAddress: json['ipAddress'] as String? ?? '-',
      macAddress: json['macAddress'] as String? ?? '-',
      airplaneModeEnabled: json['airplaneModeEnabled'] as bool? ?? false,
      mobileDataEnabled: json['mobileDataEnabled'] as bool? ?? false,
      talkbackEnabled: json['talkbackEnabled'] as bool? ?? false,
      windowAnimationScale: json['windowAnimationScale'] as String? ?? '1.0',
      transitionAnimationScale: json['transitionAnimationScale'] as String? ?? '1.0',
      animatorDurationScale: json['animatorDurationScale'] as String? ?? '1.0',
      rawResolution: json['rawResolution'] as String? ?? '-',
      hwuiProfile: json['hwuiProfile'] as String? ?? 'false',
      showTouchesEnabled: json['showTouchesEnabled'] as bool? ?? false,
      pointerLocationEnabled: json['pointerLocationEnabled'] as bool? ?? false,
    );
  }

  DeviceOverview copyWith({
    String? name,
    String? brand,
    String? model,
    String? serial,
    String? androidId,
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
    bool? wifiEnabled,
    String? ipAddress,
    String? macAddress,
    bool? airplaneModeEnabled,
    bool? mobileDataEnabled,
    bool? talkbackEnabled,
    String? windowAnimationScale,
    String? transitionAnimationScale,
    String? animatorDurationScale,
    String? rawResolution,
    String? hwuiProfile,
    bool? showTouchesEnabled,
    bool? pointerLocationEnabled,
  }) {
    return DeviceOverview(
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      serial: serial ?? this.serial,
      androidId: androidId ?? this.androidId,
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
      wifiEnabled: wifiEnabled ?? this.wifiEnabled,
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
      airplaneModeEnabled: airplaneModeEnabled ?? this.airplaneModeEnabled,
      mobileDataEnabled: mobileDataEnabled ?? this.mobileDataEnabled,
      talkbackEnabled: talkbackEnabled ?? this.talkbackEnabled,
      windowAnimationScale: windowAnimationScale ?? this.windowAnimationScale,
      transitionAnimationScale: transitionAnimationScale ?? this.transitionAnimationScale,
      animatorDurationScale: animatorDurationScale ?? this.animatorDurationScale,
      rawResolution: rawResolution ?? this.rawResolution,
      hwuiProfile: hwuiProfile ?? this.hwuiProfile,
      showTouchesEnabled: showTouchesEnabled ?? this.showTouchesEnabled,
      pointerLocationEnabled: pointerLocationEnabled ?? this.pointerLocationEnabled,
    );
  }
}
