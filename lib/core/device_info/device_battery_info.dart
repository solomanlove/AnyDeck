/// 概览页统一使用的电量与充电状态，不把电池等级误认为百分比。
enum DeviceChargingState { unknown, charging, notCharging, full }

class DeviceBatteryInfo {
  const DeviceBatteryInfo({required this.level, required this.chargingState});

  final int? level;
  final DeviceChargingState chargingState;

  /// Android BatteryService 的 level/scale 与 status 使用不同字段。
  factory DeviceBatteryInfo.fromAndroidDump(String output) {
    final rawLevel = _field(output, 'level');
    final scale = _field(output, 'scale');
    final percent = rawLevel == null
        ? null
        : scale == null
        ? rawLevel
        : scale > 0
        ? (rawLevel * 100 / scale).round()
        : null;
    final status = _field(output, 'status');
    return DeviceBatteryInfo(
      level: _percent(percent),
      chargingState: switch (status) {
        2 => DeviceChargingState.charging,
        3 || 4 => DeviceChargingState.notCharging,
        5 => DeviceChargingState.full,
        _ => DeviceChargingState.unknown,
      },
    );
  }

  /// HarmonyOS `batteryLevel` 是等级；百分比必须读取 `capacity`。
  factory DeviceBatteryInfo.fromHarmonyDump(String output) {
    final chargeStatus = _field(output, 'chargingStatus');
    return DeviceBatteryInfo(
      level: _percent(_field(output, 'capacity')),
      chargingState: switch (chargeStatus) {
        1 => DeviceChargingState.charging,
        0 || 2 => DeviceChargingState.notCharging,
        3 => DeviceChargingState.full,
        _ => DeviceChargingState.unknown,
      },
    );
  }

  factory DeviceBatteryInfo.fromJson(Map<String, dynamic> json) {
    final name = json['chargingState'] as String?;
    return DeviceBatteryInfo(
      level: _percent(json['level'] as int?),
      chargingState: DeviceChargingState.values.firstWhere(
        (value) => value.name == name,
        orElse: () => DeviceChargingState.unknown,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'level': level,
    'chargingState': chargingState.name,
  };

  static int? _field(String output, String name) {
    final match = RegExp(
      '^\\s*$name:\\s*(\\d+)\\s*\$',
      multiLine: true,
    ).firstMatch(output);
    return int.tryParse(match?.group(1) ?? '');
  }

  static int? _percent(int? value) =>
      value != null && value >= 0 && value <= 100 ? value : null;
}
