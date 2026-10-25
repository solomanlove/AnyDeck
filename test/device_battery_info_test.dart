import 'package:any_deck/core/device_info/device_battery_info.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android dumpsys battery 解析电量比例与正在充电', () {
    final info = DeviceBatteryInfo.fromAndroidDump('''
Current Battery Service state:
  AC powered: true
  status: 2
  level: 43
  scale: 100
''');

    expect(info.level, 43);
    expect(info.chargingState, DeviceChargingState.charging);
  });

  test('Android 满电与未知状态分开处理', () {
    final full = DeviceBatteryInfo.fromAndroidDump(
      'status: 5\nlevel: 100\nscale: 100',
    );
    final missing = DeviceBatteryInfo.fromAndroidDump(
      'Battery service unavailable',
    );

    expect(full.chargingState, DeviceChargingState.full);
    expect(missing.level, isNull);
    expect(missing.chargingState, DeviceChargingState.unknown);
    expect(DeviceBatteryInfo.fromAndroidDump('level: 50\nscale: 200').level, 25);
  });

  test('鸿蒙读取 capacity 百分比而非 batteryLevel 等级', () {
    final info = DeviceBatteryInfo.fromHarmonyDump('''
capacity: 100
batteryLevel: 1
chargingStatus: 3
pluggedType: 2
''');

    expect(info.level, 100);
    expect(info.chargingState, DeviceChargingState.full);
    expect(
      DeviceBatteryInfo.fromHarmonyDump(
        'capacity: 67\nchargingStatus: 1',
      ).chargingState,
      DeviceChargingState.charging,
    );
    expect(DeviceBatteryInfo.fromHarmonyDump('batteryLevel: 1').level, isNull);
  });

  test('电池数据写入概览缓存，旧缓存仍可读取', () {
    final overview = DeviceOverview.fromJson({
      'battery': const DeviceBatteryInfo(
        level: 76,
        chargingState: DeviceChargingState.notCharging,
      ).toJson(),
    });

    expect(overview.battery?.level, 76);
    expect(
      DeviceOverview.fromJson(overview.toJson()).battery?.chargingState,
      DeviceChargingState.notCharging,
    );
    expect(DeviceOverview.fromJson({}).battery, isNull);
  });
}
