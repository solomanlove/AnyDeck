import 'dart:convert';

import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

class _FakeHdcSerialService extends HdcService {
  _FakeHdcSerialService({
    this.bootSnResult,
    this.bmUdidResult,
  }) : super(executable: 'hdc');

  final String? bootSnResult;
  final String? bmUdidResult;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (command.contains('ohos.boot.sn')) {
      if (bootSnResult != null) {
        return AdbResult(exitCode: 0, stdout: bootSnResult!, stderr: '');
      }
      return const AdbResult(exitCode: 1, stdout: '[Fail]param not found', stderr: '');
    }
    if (command.contains('bm get -u')) {
      if (bmUdidResult != null) {
        return AdbResult(exitCode: 0, stdout: bmUdidResult!, stderr: '');
      }
      return const AdbResult(exitCode: 1, stdout: 'fail', stderr: '');
    }
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HdcService Device Serial Parsing Tests', () {
    test('only Connected HDC targets are online', () {
      expect(
        HdcService.connectedTargetIds([
          {'serial': '192.168.31.153:5555', 'status': 'Unknown'},
          {'serial': '192.168.31.83:5555', 'status': 'Offline'},
          {'serial': '2UCUT23C18017189', 'status': 'Connected'},
        ]),
        ['2UCUT23C18017189'],
      );
    });

    test('verbose HDC targets require explicit Connected status', () {
      expect(
        HdcService.parseConnectedTargetsWithStatus('''
192.168.31.153:5555 TCP Unknown unknown...
192.168.31.83:5555 TCP Offline localhost
2UCUT23C18017189 USB Connected localhost
192.168.31.154:5555
'''),
        ['2UCUT23C18017189'],
      );
    });

    test('parseSerialFromParamOutput extracts valid serial and ignores failures', () {
      expect(
        HdcServiceDeviceInfo.parseSerialFromParamOutput('[Fail]\n2UCUT23C18017189\n'),
        '2UCUT23C18017189',
      );
      expect(
        HdcServiceDeviceInfo.parseSerialFromParamOutput('unknown\n-\n2UCUT23C18017189'),
        '2UCUT23C18017189',
      );
      expect(
        HdcServiceDeviceInfo.parseSerialFromParamOutput('[Fail]\nfail\n-'),
        null,
      );
    });

    test('parseUdidFromBmOutput parses UDID string', () {
      expect(
        HdcServiceDeviceInfo.parseUdidFromBmOutput('udid: 70010054583239333230343734613233'),
        '70010054583239333230343734613233',
      );
      expect(
        HdcServiceDeviceInfo.parseUdidFromBmOutput('70010054583239333230343734613233'),
        '70010054583239333230343734613233',
      );
    });

    test('getDeviceSerial queries param and returns hardware SN for wireless target', () async {
      final hdc = _FakeHdcSerialService(bootSnResult: '2UCUT23C18017189\n');
      final sn = await hdc.getDeviceSerial('192.168.1.146:5555');
      expect(sn, '2UCUT23C18017189');
    });

    test('getDeviceSerial queries bm get -u when param lookup returns fail', () async {
      final hdc = _FakeHdcSerialService(bmUdidResult: 'udid: 70010054583239333230343734613233\n');
      final sn = await hdc.getDeviceSerial('192.168.1.146:5555');
      expect(sn, '70010054583239333230343734613233');
    });

    test('getDeviceSerial falls back to USB deviceId if param lookup fails', () async {
      final hdc = _FakeHdcSerialService();
      final sn = await hdc.getDeviceSerial('2UCUT23C18017189');
      expect(sn, '2UCUT23C18017189');
    });

    test('getDeviceSerial returns null for network device if all queries fail', () async {
      final hdc = _FakeHdcSerialService();
      final sn = await hdc.getDeviceSerial('192.168.1.146:5555');
      expect(sn, isNull);
    });
  });

  group('Harmony Device Registry Merge Tests', () {
    test('同一地址同时被 ADB 和 HDC 发现时保留 Android 路由', () async {
      const address = '192.168.31.153:5555';
      SharedPreferences.setMockInitialValues({
        'devices.history': [address],
      });

      final container = ProviderContainer(
        overrides: [
          devicesProvider.overrideWith((ref) => Stream.value(const [
                AdbDevice(
                  id: address,
                  status: 'device',
                  model: 'Android Phone',
                  product: 'android',
                ),
                AdbDevice(
                  id: address,
                  status: 'device',
                  model: 'HarmonyOS Device',
                  product: 'HarmonyOS NEXT',
                  isHarmony: true,
                ),
              ])),
          adbServiceProvider.overrideWithValue(FakeAdbService()),
          hdcServiceProvider.overrideWithValue(_FakeHdcSerialService()),
        ],
      );
      addTearDown(container.dispose);

      container.listen(deviceRegistryProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();

      final devices = container.read(deviceRegistryProvider);
      expect(devices, hasLength(1));
      expect(devices.single.id, address);
      expect(devices.single.isHarmony, isFalse);
      expect(devices.single.model, 'Android Phone');
      expect(devices.single.product, 'android');
    });

    test('Offline Harmony USB and Wi-Fi devices with same IP merge into single device', () async {
      SharedPreferences.setMockInitialValues({
        'devices.history': ['2UCUT23C18017189', '192.168.1.146:5555'],
        'devices.products': jsonEncode({
          '2UCUT23C18017189': 'HarmonyOS NEXT',
          '192.168.1.146:5555': 'HarmonyOS NEXT',
        }),
        'devices.models': jsonEncode({
          '2UCUT23C18017189': 'HarmonyOS Device',
          '192.168.1.146:5555': 'HarmonyOS Device',
        }),
        'devices.ips': jsonEncode({
          '192.168.1.146:5555': '192.168.1.146',
        }),
        'devices.tags': jsonEncode({
          '2UCUT23C18017189': ['鸿蒙测试机'],
        }),
        'devices.overview.2UCUT23C18017189': jsonEncode({
          'name': 'nova 12 Ultra',
          'model': 'ADA-AL00U',
          'serial': '2UCUT23C18017189',
          'ipAddress': '192.168.1.146',
          'androidVersion': 'OpenHarmony-6.1.0.115 (API 23)',
        }),
        'devices.overview.192.168.1.146:5555': jsonEncode({
          'name': 'nova 12 Ultra',
          'model': 'ADA-AL00U',
          'serial': '192.168.1.146:5555',
          'ipAddress': '192.168.1.146',
          'androidVersion': 'OpenHarmony-6.1.0.115 (API 23)',
        }),
      });

      final container = ProviderContainer(
        overrides: [
          devicesProvider.overrideWith((ref) => Stream.value(<AdbDevice>[])),
          hdcServiceProvider.overrideWithValue(_FakeHdcSerialService()),
        ],
      );
      addTearDown(container.dispose);

      // 触发初始构建
      container.read(deviceRegistryProvider);

      // 等待异步 _loadFromPrefs 完成加载与合并
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await pumpEventQueue();

      final registeredDevices = container.read(deviceRegistryProvider);

      // 验证两条离线记录已合并为 1 条
      expect(registeredDevices.length, 1);
      final merged = registeredDevices.first;
      expect(merged.id, '2UCUT23C18017189');
      expect(merged.serial, '2UCUT23C18017189');
      expect(merged.isHarmony, isTrue);
      expect(merged.tags, contains('鸿蒙测试机'));
      expect(merged.wifiIp, '192.168.1.146');
      expect(merged.connections, containsAll(['2UCUT23C18017189', '192.168.1.146:5555']));
    });
  });
}
