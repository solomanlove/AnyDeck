import 'dart:async';

import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/wireless/adb_wireless_coordinator.dart';
import 'package:any_deck/core/adb/wireless/adb_wireless_probe.dart';
import 'package:any_deck/core/adb/wireless/adb_wireless_state.dart';
import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wireless_adb_fake.dart';

void main() {
  late WirelessAdbFake adb;
  late AdbWirelessCoordinator flow;
  late List<AdbWirelessState> states;
  setUp(() {
    adb = WirelessAdbFake();
    states = [];
    flow = AdbWirelessCoordinator(
      adb,
      onState: states.add,
      restartDelay: Duration.zero,
      readyTimeout: const Duration(milliseconds: 20),
      pollDelay: const Duration(milliseconds: 1),
      detachGrace: const Duration(milliseconds: 25),
    );
  });
  tearDown(() => flow.dispose());
  List<List<String>> commands(String name) =>
      adb.calls.where((a) => a.contains(name)).toList();

  test('USB 授权上线后自动开启监听，再读取 IP；不自动 connect', () async {
    adb.add('PHONE', 'PHONE');
    flow.observe([const AdbDevice(id: 'PHONE', status: 'unauthorized')]);
    await Future<void>.delayed(Duration.zero);
    expect(adb.calls, isEmpty);
    flow.observe([const AdbDevice(id: 'PHONE', status: 'device')]);
    await flow.waitForPreparation('PHONE');
    expect(commands('tcpip'), hasLength(1));
    expect(commands('connect'), isEmpty);
    expect(states.last.ip, '192.168.1.8');
    expect(states.last.messageKey, 'wirelessReady');
    expect(
      adb.calls.indexWhere((a) => a.contains('tcpip')),
      lessThan(adb.calls.indexWhere((a) => a.contains('route'))),
    );
  });

  test('adbd 重启导致的离线和重复快照不重复开启监听', () async {
    adb.add('PHONE', 'PHONE');
    adb.enableGate = Completer<void>();
    const device = AdbDevice(id: 'PHONE', status: 'device');
    flow.observe([device]);
    await Future<void>.delayed(Duration.zero);
    flow.observe([]);
    flow.observe([device]);
    flow.observe([device]);
    adb.enableGate!.complete();
    await flow.waitForPreparation('PHONE');
    expect(commands('tcpip'), hasLength(1));
  });

  test('已开启监听时跳过重启，刷新 DHCP 地址而非使用传入旧 IP', () async {
    adb.add('PHONE', 'PHONE', ip: '192.168.1.9');
    adb.ports['PHONE'] = '5555';
    adb.add('192.168.1.9:5555', 'PHONE', connected: false);
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      source: 'PHONE',
      ip: '192.168.1.8',
    );
    expect(result.isSuccess, isTrue);
    expect(commands('tcpip'), isEmpty);
    expect(commands('connect').first, ['connect', '192.168.1.9:5555']);
  });

  test('TCP 成功后无需 mDNS，重复点击合并连接任务', () async {
    adb.add('192.168.1.8:5555', 'PHONE', connected: false);
    final results = await Future.wait([
      flow.connect(key: 'PHONE', serial: 'PHONE', ip: '192.168.1.8'),
      flow.connect(key: 'PHONE', serial: 'PHONE', ip: '192.168.1.8'),
    ]);
    expect(results.every((r) => r.isSuccess), isTrue);
    expect(commands('connect'), hasLength(1));
    expect(commands('mdns'), isEmpty);
  });

  test('exitCode 0 的失败 connect 不视为成功，mDNS 只连接目标手机', () async {
    adb.add('192.168.1.9:37001', 'PHONE', ip: '192.168.1.9', connected: false);
    adb.mdns = '''
adb-OTHER-abc _adb-tls-connect._tcp 192.168.1.20:37002
adb-PHONE-abc (2) _adb-tls-connect._tcp 192.168.1.9:37001
''';
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      ip: '192.168.1.8',
    );
    expect(result.messageKey, 'wirelessConnected');
    expect(
      commands('connect').any((a) => a[1].contains('192.168.1.20')),
      isFalse,
    );
    expect(states.any((s) => s.messageKey == 'wirelessDiscovering'), isTrue);
    expect(commands('tcpip').single[1], '192.168.1.9:37001');
    expect(adb.online, contains('192.168.1.9:5555'));
    expect(adb.online, isNot(contains('192.168.1.9:37001')));
  });

  test('旧 IP 被其他手机使用时不得向其发送 tcpip', () async {
    adb.add('192.168.1.8:5555', 'OTHER', connected: false);
    adb.add('192.168.1.8:37001', 'OTHER', connected: false);
    adb.mdns = 'adb-OTHER-abc _adb-tls-connect._tcp 192.168.1.8:37001';
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      ip: '192.168.1.8',
    );
    expect(result.isSuccess, isFalse);
    expect(commands('tcpip'), isEmpty);
  });

  test('mDNS 同时发现传统 TCP 和 TLS 时优先传统 TCP', () async {
    adb.add('192.168.1.9:5555', 'PHONE', ip: '192.168.1.9', connected: false);
    adb.mdns = '''
adb-PHONE-abc _adb-tls-connect._tcp 192.168.1.9:37001
adb-PHONE _adb._tcp 192.168.1.9:5555
''';
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      ip: '192.168.1.8',
    );
    expect(result.messageKey, 'wirelessConnected');
    expect(commands('tcpip'), isEmpty);
    expect(commands('connect').last[1], '192.168.1.9:5555');
  });

  test('TLS 转 TCP 失败后恢复已授权 TLS 并返回明确降级提示', () async {
    adb.add('192.168.1.8:37001', 'PHONE');
    adb.tcpStarts = false;
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      source: '192.168.1.8:37001',
      ip: '192.168.1.8',
    );
    expect(result.isSuccess, isTrue);
    expect(result.messageKey, 'wirelessTlsFallback');
    expect(adb.online, contains('192.168.1.8:37001'));
    expect(commands('disconnect'), isEmpty);
  });

  test('TCP 确认可用后只断开同机 TLS，不改手机设置或共享 ADB Server', () async {
    adb.add('192.168.1.8:5555', 'PHONE', connected: false);
    adb.add('192.168.1.8:37001', 'PHONE');
    adb.add('192.168.1.20:37001', 'OTHER');
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      ip: '192.168.1.8',
      connections: ['192.168.1.8:37001', '192.168.1.20:37001'],
    );
    expect(result.isSuccess, isTrue);
    expect(commands('disconnect'), [
      ['disconnect', '192.168.1.8:37001'],
    ]);
    expect(commands('kill-server'), isEmpty);
    expect(commands('settings'), isEmpty);
  });

  test('配对后只用 mDNS 连接端口，然后切换 TCP，不使用配对端口连接', () async {
    adb.add('192.168.1.8:37001', 'PHONE', connected: false);
    adb.mdns = 'adb-PHONE-abc _adb-tls-connect._tcp 192.168.1.8:37001';
    final result = await flow.pair('192.168.1.8:40001', '123456');
    expect(result.messageKey, 'wirelessConnected');
    expect(
      commands('connect').any((a) => a[1] == '192.168.1.8:40001'),
      isFalse,
    );
    expect(commands('tcpip'), hasLength(1));
  });

  test('iOS、HDC、模拟器与未授权设备不触发自动准备', () async {
    flow.observe([
      const AdbDevice(id: 'IPHONE', status: 'device', isIos: true),
      const AdbDevice(id: 'HDC', status: 'device', isHarmony: true),
      const AdbDevice(id: 'emulator-5554', status: 'device'),
      const AdbDevice(id: 'PHONE', status: 'unauthorized'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(adb.calls, isEmpty);
  });

  test('销毁后停止排队任务和后续探测', () async {
    adb.add('PHONE', 'PHONE');
    adb.enableGate = Completer<void>();
    final job = flow.prepareUsb('PHONE');
    await Future<void>.delayed(Duration.zero);
    flow.dispose();
    final count = adb.calls.length;
    adb.enableGate!.complete();
    await job;
    expect(adb.calls.length, count);
  });

  test('USB ID 与硬件 serial 不同仍可连接，并使用真实身份校验 TCP', () async {
    adb.add('USB_ID', 'REAL_SERIAL');
    final result = await flow.connect(
      key: 'USB_ID',
      serial: 'USB_ID',
      source: 'USB_ID',
    );
    expect(result.messageKey, 'wirelessConnected');
    expect(states.last.serial, 'REAL_SERIAL');
  });

  test('手机重启或长时间拔线后允许再次准备监听', () async {
    adb.add('PHONE', 'PHONE');
    const device = AdbDevice(id: 'PHONE', status: 'device');
    flow.observe([device]);
    await flow.waitForPreparation('PHONE');
    flow.observe([]);
    await Future<void>.delayed(const Duration(milliseconds: 35));
    adb.ports.clear();
    flow.observe([device]);
    await flow.waitForPreparation('PHONE');
    expect(commands('tcpip'), hasLength(2));
  });

  test('没有 Wi-Fi IP 时准备超时，并明确清空旧地址缓存', () async {
    adb.add('PHONE', 'PHONE');
    await flow.prepareUsb('PHONE');
    adb.ips.clear();
    final result = await flow.prepareUsb('PHONE');
    expect(result.messageKey, 'wirelessNoIp');
    expect(states.last.registryIp, '-');
    expect(states.last.busy, isFalse);
  });

  test('TLS 重启导致连接端口变化时通过新 mDNS 端口恢复', () async {
    adb.add('192.168.1.8:37001', 'PHONE');
    adb.tcpStarts = false;
    adb.onEnable = (id) {
      adb.reachable.remove(id);
      adb.add('192.168.1.8:37002', 'PHONE', connected: false);
      adb.mdns = 'adb-PHONE-new _adb-tls-connect._tcp 192.168.1.8:37002';
    };
    final result = await flow.connect(
      key: 'PHONE',
      serial: 'PHONE',
      source: '192.168.1.8:37001',
    );
    expect(result.messageKey, 'wirelessTlsFallback');
    expect(adb.online, contains('192.168.1.8:37002'));
  });

  test('IP 解析优先 Wi-Fi src，不选择网关、VPN 或蜂窝网络', () {
    expect(
      AdbWirelessProbe.parseWifiRoute('''
default via 10.0.0.1 dev rmnet0 src 10.0.0.2
10.8.0.0/24 dev tun0 src 10.8.0.2
default via 192.168.1.1 dev wlan0
192.168.1.0/24 dev wlan0 proto kernel scope link src 192.168.1.8
'''),
      '192.168.1.8',
    );
    expect(
      AdbWirelessProbe.parseWifiAddress(
        '5: wlan1 inet 192.168.2.8/24 scope global',
      ),
      '192.168.2.8',
    );
  });

  test('mDNS TLS 服务名不被当作 TCP 或 IP，命令仍优先 USB/TCP', () {
    const tls = 'adb-PHONE-abc (2)._adb-tls-connect._tcp';
    const wireless = RegisteredDevice(
      id: tls,
      status: 'device',
      isOnline: true,
      connections: [tls],
    );
    expect(wireless.hasTcpConnection, isFalse);
    expect(wireless.hasWifiDebuggingConnection, isTrue);
    expect(wireless.wifiIp, isNull);
    expect(
      wireless
          .copyWith(connections: [tls, '192.168.1.8:5555'])
          .preferredCommandId,
      '192.168.1.8:5555',
    );
    expect(
      wireless
          .copyWith(connections: [tls, 'PHONE', '192.168.1.8:5555'])
          .preferredCommandId,
      'PHONE',
    );
  });
}
