import 'dart:async';
import 'dart:convert';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/modules/harmony_device_ip_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = DiscoveredDevice(
  id: 'HARMONY',
  status: 'device',
  model: 'nova 12 Ultra',
  isHarmony: true,
);

/// 通过可控 WLAN 响应模拟换网、Wi-Fi 关闭和查询超时。
class _WifiHdc extends HdcService {
  _WifiHdc() : super(executable: 'hdc');

  String? ip = '192.168.31.83';
  int calls = 0;
  bool fail = false;
  Completer<AdbResult>? pending;

  @override
  Future<AdbResult> shell(
    String deviceId,
    String command, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    expectSync(deviceId, 'HARMONY');
    expectSync(command, 'ifconfig wlan0');
    expectSync(timeout, const Duration(seconds: 3));
    calls++;
    if (pending != null) return pending!.future;
    return AdbResult(
      exitCode: fail ? 124 : 0,
      stdout: ip == null
          ? 'wlan0 UP'
          : 'wlan0\n inet addr:$ip Mask:255.255.255.0',
      stderr: '',
    );
  }
}

/// 排空 Provider 的依赖重建、Stream 投递与持久化微任务。
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('完整历史缓存仍查询当前 WLAN，并在换网和关闭 Wi-Fi 后同步注册表', (tester) async {
    SharedPreferences.setMockInitialValues({
      'devices.history': ['HARMONY'],
      'devices.ips': jsonEncode({'HARMONY': '192.168.1.18'}),
      'devices.models': jsonEncode({'HARMONY': 'nova 12 Ultra'}),
      'devices.overview.HARMONY': jsonEncode({
        'serial': 'HARMONY',
        'ipAddress': '192.168.1.18',
        'androidVersion': 'OpenHarmony-6.1.0.115 (API 23)',
      }),
    });
    final hdc = _WifiHdc();
    final container = ProviderContainer(
      overrides: [
        hdcServiceProvider.overrideWithValue(hdc),
        discoveredDevicesProvider.overrideWith((ref) => Stream.value([_phone])),
      ],
    );
    container.listen(deviceRegistryProvider, (_, _) {});
    await _flush(tester);
    await _flush(tester);
    expect(
      container.read(deviceRegistryProvider).single.wifiIp,
      '192.168.31.83',
    );

    hdc.ip = '192.168.31.90';
    await tester.pump(const Duration(seconds: 10));
    await _flush(tester);
    expect(container.read(deviceRegistryProvider).single.wifiIp, hdc.ip);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('devices.ips')!)['HARMONY'], hdc.ip);

    hdc.fail = true;
    await tester.pump(const Duration(seconds: 10));
    await _flush(tester);
    expect(container.read(deviceRegistryProvider).single.wifiIp, hdc.ip);

    hdc.fail = false;
    hdc.ip = null;
    await tester.pump(const Duration(seconds: 10));
    await _flush(tester);
    expect(container.read(deviceRegistryProvider).single.wifiIp, isNull);
    container.dispose();
    await _flush(tester);
  });

  testWidgets('重复发现不重复查询，慢查询互斥，离线和销毁后停止查询', (tester) async {
    final hdc = _WifiHdc()..pending = Completer<AdbResult>();
    final discovery = StreamController<List<DiscoveredDevice>>();
    final container = ProviderContainer(
      overrides: [
        hdcServiceProvider.overrideWithValue(hdc),
        discoveredDevicesProvider.overrideWith((ref) => discovery.stream),
      ],
    );
    container.listen(harmonyDeviceIpsProvider, (_, _) {});
    discovery.add([_phone]);
    await _flush(tester);
    expect(hdc.calls, 1);
    discovery.add([_phone]);
    await tester.pump(const Duration(seconds: 20));
    expect(hdc.calls, 1);

    discovery.add([]);
    await _flush(tester);
    hdc.pending!.complete(const AdbResult(exitCode: 0, stdout: '', stderr: ''));
    await tester.pump(const Duration(seconds: 20));
    expect(hdc.calls, 1);
    expect(container.read(harmonyDeviceIpsProvider).value, isEmpty);

    container.dispose();
    unawaited(discovery.close());
    await tester.pump(const Duration(seconds: 20));
    expect(hdc.calls, 1);
  });

  testWidgets('子窗口不启动额外 WLAN 查询', (tester) async {
    final hdc = _WifiHdc();
    final container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('mirror-window'),
        hdcServiceProvider.overrideWithValue(hdc),
        discoveredDevicesProvider.overrideWith((ref) => Stream.value([_phone])),
      ],
    );
    container.listen(harmonyDeviceIpsProvider, (_, _) {});
    await tester.pump(const Duration(seconds: 20));
    expect(hdc.calls, 0);
    container.dispose();
  });
}
