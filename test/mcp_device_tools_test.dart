import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/device_info/device_info_service.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/mcp/tools/mcp_device_tools.dart';
import 'package:any_deck/core/mcp/tools/mcp_battery_snapshot.dart';

/// 有界模拟设备输出，不访问用户真机。
class _Adb extends AdbService {
  bool fails = false;
  String state = 'offline';
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (args.contains('get-state')) {
      return AdbResult(
        exitCode: state == 'device' ? 0 : 1,
        stdout: state == 'device' ? state : '',
        stderr: 'device $state',
      );
    }
    if (fails) {
      return const AdbResult(exitCode: 1, stdout: '', stderr: 'device offline');
    }
    return AdbResult(
      exitCode: 0,
      stderr: '',
      stdout: args.contains('getprop')
          ? '[ro.product.model]: [test model]\n[ro.product.brand]: [test brand]'
          : '',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Adb adb;
  late DeviceInfoService service;
  late McpDeviceTools tools;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    adb = _Adb();
    service = DeviceInfoService(adb);
    tools = McpDeviceTools(adbService: adb, deviceInfoService: service);
  });
  Future<Map<String, dynamic>> detail() => tools
      .getTools()
      .firstWhere((t) => t.name == 'get_device_detail')
      .handler({'deviceId': 'phone'});

  test('旧缓存离线返回明确来源与未知采集时间，不冒充实时数据', () async {
    SharedPreferences.setMockInitialValues({
      'devices.overview.phone': jsonEncode({'name': 'historical phone'}),
    });
    adb.fails = true;
    final data = await detail();
    expect(data['name'], 'historical phone');
    expect(data['connectionState'], 'offline');
    expect(data['dataSource'], 'cache');
    expect(data['stale'], true);
    expect(data['collectedAt'], isNull);
    expect(DateTime.tryParse(data['checkedAt']), isNotNull);
    expect(data['readError'], contains('offline'));
  });

  test('实时查询写入采集时间，断线后返回原时间而非本次读取时间', () async {
    final live = await detail();
    expect(live['dataSource'], 'live');
    expect(live['connectionState'], 'online');
    expect(live['stale'], false);
    expect(live['model'], 'test model');
    final cached = await service.loadCachedSnapshot('phone');
    expect(cached?.collectedAt, isNotNull);
    adb.fails = true;
    final offline = await detail();
    expect(offline['collectedAt'], cached!.collectedAt!.toIso8601String());
    expect(offline['dataSource'], 'cache');
  });

  test('无缓存的读取失败明确为 unavailable，不生成占位详情', () async {
    adb.fails = true;
    final data = await detail();
    expect(data['dataSource'], 'unavailable');
    expect(data.containsKey('model'), false);
    expect(data['collectedAt'], null);
    expect(data['readError'], isNotEmpty);
  });

  test('详情读取失败但 transport 在线时保留在线状态和缓存标识', () async {
    await service.saveToCache(
      'phone',
      DeviceOverview.fromJson({'name': 'old'}),
    );
    adb.fails = true;
    adb.state = 'device';
    final data = await detail();
    expect(data['connectionState'], 'online');
    expect(data['dataSource'], 'cache');
    expect(data['stale'], true);
  });

  test('UI 默认缓存回退仍兼容，实时调用可禁止隐式回退', () async {
    await service.saveToCache(
      'phone',
      DeviceOverview.fromJson({'name': 'old'}),
    );
    adb.fails = true;
    expect((await service.loadOverview('phone')).name, 'old');
    await expectLater(
      service.loadOverview('phone', allowCachedFallback: false),
      throwsA(isA<AdbException>()),
    );
  });

  test('缓存时间 round-trip、旧时间未知与清理', () async {
    final when = DateTime.utc(2026, 10, 20);
    await service.saveToCache(
      'phone',
      DeviceOverview.fromJson({}),
      collectedAt: when,
    );
    expect((await service.loadCachedSnapshot('phone'))!.collectedAt, when);
    await service.saveToCache('phone', DeviceOverview.fromJson({}));
    expect((await service.loadCachedSnapshot('phone'))!.collectedAt, null);
    await service.clearDeviceCache('phone');
    expect(await service.loadCachedSnapshot('phone'), null);
  });

  test('电池温度、电压、比例和枚举带语义且保留原字段', () {
    final data = McpBatterySnapshot.parse(
      'level: 50\nscale: 200\n'
      'status: 3\nhealth: 2\ntemperature: 350\nvoltage: 4293',
    );
    expect(data['temperature'], '350');
    expect(data['normalized'], {
      'levelPercent': 25.0,
      'temperatureCelsius': 35.0,
      'voltageVolts': 4.293,
      'status': 'discharging',
      'health': 'good',
    });
    expect(data['rawUnits']['temperature'], '0.1 °C');
  });

  test('电池负温度可用，缺失、非法值和未知枚举不补零', () {
    final data = McpBatterySnapshot.parse(
      'temperature: -25\nvoltage: -1\n'
      'level: 150\nscale: 100\nstatus: 99\nhealth: bad',
    )['normalized'];
    expect(data['temperatureCelsius'], -2.5);
    expect(data['voltageVolts'], null);
    expect(data['levelPercent'], null);
    expect(data['status'], 'unknown');
    expect(data['health'], 'unknown');
    expect(
      McpBatterySnapshot.parse('')['normalized']['temperatureCelsius'],
      null,
    );
  });
}
