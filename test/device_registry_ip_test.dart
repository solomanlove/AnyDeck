import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wireless_adb_fake.dart';

const _oldIp = '192.168.10.241';
const _currentIp = '192.168.0.100';
const _tcp = '$_currentIp:5555';

/// 构造同一物理设备的历史与在线通道，验证缓存不能遮盖真实连接地址。
List<RegisteredDevice> _merge(List<AdbDevice> active) {
  return DeviceRegistryMerger.mergeDevices(
    activeDevices: active,
    historyIds: ['PHONE', '$_oldIp:5555', _tcp],
    aliases: const {},
    models: const {},
    products: const {},
    ipAddresses: const {'PHONE': _oldIp},
    androidVersions: const {},
    sdkVersions: const {},
    remarks: const {},
    tags: const {},
    checkedIds: const {},
    serialMap: const {'$_oldIp:5555': 'PHONE', _tcp: 'PHONE'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('单独 TCP 上线时，真实地址覆盖 serial 的历史 IP', () {
    final device = _merge(const [AdbDevice(id: _tcp, status: 'device')]).single;
    expect(device.id, _tcp);
    expect(device.connections, [_tcp]);
    expect(device.ipAddress, _currentIp);
    expect(device.wifiIp, _currentIp);
  });

  test('USB 与 TCP 合并后仍走 USB 命令，但 IP 使用在线 TCP 地址', () {
    final device = _merge(const [
      AdbDevice(id: 'PHONE', status: 'device'),
      AdbDevice(id: _tcp, status: 'device'),
    ]).single;
    expect(device.preferredCommandId, 'PHONE');
    expect(device.connections, ['PHONE', _tcp]);
    expect(device.ipAddress, _currentIp);
    expect(device.wifiIp, _currentIp);
  });

  test('离线或未授权网络通道不能覆盖 USB 查询的缓存地址', () {
    for (final status in ['offline', 'unauthorized']) {
      final device = _merge([
        const AdbDevice(id: 'PHONE', status: 'device'),
        AdbDevice(id: _tcp, status: status),
      ]).single;
      expect(device.connections, ['PHONE']);
      expect(device.connectedNetworkIp, isNull);
      expect(device.wifiIp, _oldIp);
    }
    final offline = _merge(const []).single;
    expect(offline.connectedNetworkIp, isNull);
    expect(offline.wifiIp, _oldIp);
  });

  test('TCP 与 TLS 同时在线时优先 TCP，不依赖通道遍历顺序', () {
    const device = RegisteredDevice(
      id: 'PHONE',
      status: 'device',
      isOnline: true,
      connections: ['PHONE', '192.168.0.101:37123', _tcp],
      ipAddress: _oldIp,
    );
    expect(device.wifiIp, _currentIp);
    expect(
      device.copyWith(connections: ['192.168.0.101:37123']).wifiIp,
      '192.168.0.101',
    );
  });

  test('mDNS、回环和非法地址保留已探测的 Wi-Fi IP', () {
    for (final id in [
      'adb-PHONE-abc._adb-tls-connect._tcp',
      'adb-PHONE-abc._adb._tcp',
      '127.0.0.1:5555',
      '999.168.0.100:5555',
      'emulator-5554',
    ]) {
      final device = RegisteredDevice(
        id: id,
        status: 'device',
        isOnline: true,
        ipAddress: _oldIp,
      );
      expect(device.connectedNetworkIp, isNull, reason: id);
      expect(device.wifiIp, _oldIp, reason: id);
    }
  });

  test('单网络通道无需 connections 或缓存也可显示当前地址', () {
    const device = RegisteredDevice(id: _tcp, status: 'device', isOnline: true);
    expect(device.wifiIp, _currentIp);
    expect(device.copyWith(ipAddress: _oldIp).wifiIp, _currentIp);
  });

  test('手动 TCP 上线覆盖磁盘旧 IP，并在断开、重新加载后保留新地址', () async {
    SharedPreferences.setMockInitialValues({
      'devices.history': ['PHONE', _tcp],
      'devices.ips': jsonEncode({'PHONE': _oldIp, _tcp: _oldIp}),
      'devices.models': jsonEncode({'PHONE': 'Pixel', _tcp: 'Pixel'}),
      'devices.overview.$_tcp': jsonEncode({
        'serial': 'PHONE',
        'ipAddress': _oldIp,
        'androidVersion': 'Android 16 (API 36)',
      }),
    });
    final stream = StreamController<List<AdbDevice>>();
    addTearDown(stream.close);
    final adb = WirelessAdbFake()..add(_tcp, 'PHONE', ip: _currentIp);
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        devicesProvider.overrideWith((ref) => stream.stream),
      ],
    );
    addTearDown(container.dispose);
    container.listen(deviceRegistryProvider, (_, _) {});
    await pumpEventQueue();
    stream.add(const [AdbDevice(id: _tcp, status: 'device', model: 'Pixel')]);
    await pumpEventQueue();

    final online = container.read(deviceRegistryProvider).single;
    expect(online.ipAddress, _currentIp);
    expect(online.wifiIp, _currentIp);
    final prefs = await SharedPreferences.getInstance();
    final ips = jsonDecode(prefs.getString('devices.ips')!) as Map;
    expect(ips['PHONE'], _currentIp);
    expect(ips[_tcp], _currentIp);
    // 已有完整元数据时也能纠正 IP，不增加 ADB 轮询或重启 adbd。
    expect(adb.calls, isEmpty);

    stream.add(const []);
    await pumpEventQueue();
    expect(container.read(deviceRegistryProvider).single.isOnline, isFalse);
    expect(container.read(deviceRegistryProvider).single.wifiIp, _currentIp);
    container.invalidate(deviceRegistryProvider);
    await pumpEventQueue();
    expect(container.read(deviceRegistryProvider).single.wifiIp, _currentIp);
  });
}
