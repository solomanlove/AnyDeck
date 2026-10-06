import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wireless_adb_fake.dart';

/// 验证发现数据直达设备列表，并兼容旧缓存和断线重连。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧 iOS 缓存无需进入概览即可显示型号和版本，别名仍优先', () {
    final device = DeviceRegistryMerger.mergeDevices(
      activeDevices: const [],
      historyIds: const ['test-phone'],
      aliases: const {'test-phone': '测试手机'},
      models: const {'test-phone': 'iPhone OS (iPhone8,1)'},
      products: const {'test-phone': '15.8.8'},
      ipAddresses: const {},
      androidVersions: const {},
      sdkVersions: const {},
      remarks: const {},
      tags: const {},
      checkedIds: const {},
      serialMap: const {},
    ).single;
    expect(device.model, 'iPhone 6s');
    expect(device.displayName, '测试手机');
    expect(device.androidVersion, 'iOS 15.8.8');
    expect(device.isIos, isTrue);
    expect(device.isOnline, isFalse);
  });

  test('首次连接、重连更新、缺失版本和重新加载均保留真实信息且不调用 ADB', () async {
    SharedPreferences.setMockInitialValues({});
    final stream = StreamController<List<AdbDevice>>();
    addTearDown(stream.close);
    final adb = WirelessAdbFake();
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        devicesProvider.overrideWith((ref) => stream.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(deviceRegistryProvider, (_, _) {});
    await pumpEventQueue();

    void connect(String version, {String connection = 'Network'}) {
      stream.add(
        IosDeviceService.parseDeviceListOutput(
          jsonEncode({
            'Udid': 'test-phone',
            'ProductName': 'iPhone OS',
            'ProductType': 'iPhone8,1',
            'ProductVersion': version,
            'ConnectionType': connection,
          }),
        ),
      );
    }

    connect('15.8.8');
    await pumpEventQueue();
    var device = container.read(deviceRegistryProvider).single;
    expect(device.displayName, 'iPhone 6s');
    expect(device.androidVersion, 'iOS 15.8.8');
    expect(device.isOnline, isTrue);
    expect(device.hasIosNetworkConnection, isTrue);
    expect(device.hasUsbConnection, isFalse);
    expect(device.hasTcpConnection, isFalse);
    expect(device.hasWifiDebuggingConnection, isFalse);
    expect(device.preferredCommandId, 'test-phone');
    expect(device.copyWith().toAdbDevice.iosConnectionTypes, device.iosConnectionTypes);

    // 同一 UDID 从网络切换到 USB，注册表必须刷新且移除已断开的通道。
    connect('15.8.8', connection: 'USB');
    await pumpEventQueue();
    device = container.read(deviceRegistryProvider).single;
    expect(device.hasUsbConnection, isTrue);
    expect(device.hasIosNetworkConnection, isFalse);

    // 概览的旧版本缓存不能遮盖重连时的实际系统版本。
    container
        .read(deviceRegistryProvider.notifier)
        .updateDeviceAndroidVersion('test-phone', 'iOS 15.8.7');
    stream.add(const []);
    await pumpEventQueue();
    connect('15.8.9');
    await pumpEventQueue();
    expect(
      container.read(deviceRegistryProvider).single.androidVersion,
      'iOS 15.8.9',
    );
    connect('iOS');
    await pumpEventQueue();
    expect(
      container.read(deviceRegistryProvider).single.androidVersion,
      'iOS 15.8.9',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString('devices.models')!)['test-phone'],
      'iPhone 6s',
    );
    expect(
      jsonDecode(prefs.getString('devices.products')!)['test-phone'],
      '15.8.9',
    );
    stream.add(const []);
    await pumpEventQueue();
    container.invalidate(deviceRegistryProvider);
    await pumpEventQueue();
    device = container.read(deviceRegistryProvider).single;
    expect(device.isOnline, isFalse);
    expect(device.iosConnectionTypes, isEmpty);
    expect(device.hasUsbConnection, isFalse);
    expect(device.displayName, 'iPhone 6s');
    expect(device.androidVersion, 'iOS 15.8.9');
    expect(adb.calls, isEmpty);
  });
}
