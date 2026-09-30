import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wireless_adb_fake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('主窗口注册表自动准备 USB，实时 IP 回写到合并设备', () async {
    SharedPreferences.setMockInitialValues({});
    final adb = WirelessAdbFake()..add('PHONE', 'PHONE');
    adb.ports['PHONE'] = '5555';
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        devicesProvider.overrideWith(
          (ref) => Stream.value([
            const AdbDevice(id: 'PHONE', status: 'device', model: 'Pixel'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(deviceRegistryProvider, (_, _) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      container.read(wirelessConnectionProvider)['PHONE']?.messageKey,
      'wirelessReady',
    );
    expect(container.read(deviceRegistryProvider).single.wifiIp, '192.168.1.8');
    expect(adb.calls.where((a) => a.contains('route')), isNotEmpty);
    expect(adb.calls.where((a) => a.contains('tcpip')), isEmpty);
  });

  test('子窗口不得自动准备或执行连接，避免多个 Isolate 重启同一 adbd', () async {
    final adb = WirelessAdbFake()..add('PHONE', 'PHONE');
    final container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('child-window'),
        adbServiceProvider.overrideWithValue(adb),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(wirelessConnectionProvider.notifier);
    controller.observe([const AdbDevice(id: 'PHONE', status: 'device')]);
    final result = await controller.connect(
      const RegisteredDevice(
        id: 'PHONE',
        status: 'device',
        isOnline: true,
        serial: 'PHONE',
      ),
    );
    expect(result.messageKey, 'wirelessMainOnly');
    expect(adb.calls, isEmpty);
  });

  test('USB 与物理 serial 合并后展示最近状态，不被旧失败记录遮挡', () {
    const device = RegisteredDevice(
      id: 'USB',
      serial: 'PHONE',
      status: 'device',
      isOnline: true,
    );
    const states = {
      'USB': AdbWirelessState(
        deviceId: 'USB',
        messageKey: 'wirelessNoIp',
        failed: true,
      ),
      'PHONE': AdbWirelessState(
        deviceId: 'PHONE',
        serial: 'PHONE',
        messageKey: 'wirelessConnected',
      ),
    };
    expect(wirelessStateFor(states, device)?.messageKey, 'wirelessConnected');
  });
}
