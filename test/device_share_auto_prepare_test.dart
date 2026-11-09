import 'dart:async';

import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_share/adb/shared_adb_backend.dart';
import 'package:any_deck/core/device_share/device_share_auto_prepare.dart';
import 'package:any_deck/core/device_share/device_share_invitation.dart';
import 'package:any_deck/core/device_share/device_share_models.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/device_share/device_share_store.dart';
import 'package:any_deck/core/device_share/share_tls_identity.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/device_share_fixture.dart';

const _phone = DiscoveredDevice(
  id: 'phone',
  status: 'device',
  transportId: '72',
);

class _Devices extends FakeAdbService {
  List<DiscoveredDevice> devices = [_phone];
  @override
  Future<List<DiscoveredDevice>> listDevices() async => devices;
}

class _DelayedBackend extends SharedAdbBackend {
  _DelayedBackend(int port, this.opening, this.gate)
    : super(transportId: '72', name: 'test phone', port: port);
  final Completer<void> opening, gate;
  @override
  Future<String> banner() async {
    opening.complete();
    await gate.future;
    return super.banner();
  }
}

DeviceShareEnvironment _environment(
  String? wifi, {
  List<DiscoveredDevice> devices = const [_phone],
  bool verified = true,
}) => DeviceShareEnvironment(
  network: HostNetworkInfo(
    ssid: wifi,
    verifiedWifiSsid: verified ? wifi : null,
    isWifiAddress: wifi != null,
    address: const HostNetworkAddress('test', '127.0.0.1'),
  ),
  devices: devices,
);

/// 用真实 TLS 监听和 Smart Socket 桩模拟切网、重启及手机 transport 变化。
void main() {
  late ShareTlsIdentity identity;
  late ShareAdbFixture source;
  late _Devices adb;
  late DeviceShareService service;
  late MemoryDeviceShareStore store;
  late SavedDeviceShare profile;
  late DateTime clock;
  setUpAll(() async {
    identity = await ShareTlsIdentity.generate(persistent: true);
  });
  setUp(() async {
    source = ShareAdbFixture();
    await source.start();
    adb = _Devices();
    clock = DateTime.now().toUtc();
    profile = SavedDeviceShare(
      deviceId: 'phone',
      serial: 'phone',
      name: 'test phone',
      identity: identity,
      token: DeviceShareInvitation.createToken(),
      wifiSsid: 'Office',
    );
    store = MemoryDeviceShareStore()
      ..value = DeviceShareSavedState(profiles: [profile]);
    service = DeviceShareService(
      adb,
      store: store,
      now: () => clock,
      backendFactory: (device, name) => SharedAdbBackend(
        transportId: device.transportId!,
        name: name,
        port: source.server.port,
      ),
    );
    await service.initialize();
  });
  tearDown(() async {
    await service.dispose();
    await source.close();
  });

  test('回到指定 Wi-Fi 自动准备，切换到其他网络立即撤销', () async {
    await service.updateEnvironment(_environment('Home'));
    expect(service.hosts, isEmpty);
    await service.updateEnvironment(_environment('Office'));
    final first = service.hosts.single;
    expect(first.connected, isFalse);
    expect(first.invitation.resumable, isTrue);
    expect(first.invitation.expiresAt, clock.add(const Duration(minutes: 30)));
    await service.updateEnvironment(_environment('Home'));
    expect(first.closed, isTrue);
    expect(service.hosts, isEmpty);
    await service.updateEnvironment(_environment('Office'));
    expect(
      service.hosts.single.invitation.fingerprint,
      first.invitation.fingerprint,
    );
    expect(service.hosts.single.invitation.token, first.invitation.token);
  });

  test('手机不在线时等待；同一手机回归后创建新会话但不延长本次期限', () async {
    await service.updateEnvironment(_environment('Office'));
    final original = service.hosts.single;
    final deadline = original.invitation.expiresAt;
    await service.updateEnvironment(_environment('Office', devices: []));
    expect(service.hosts, isEmpty);
    clock = clock.add(const Duration(minutes: 5));
    source.transportId = '99';
    const reconnected = DiscoveredDevice(
      id: 'phone',
      status: 'device',
      transportId: '99',
    );
    await service.updateEnvironment(
      _environment('Office', devices: [reconnected]),
    );
    final next = service.hosts.single;
    expect(next.backend.transportId, '99');
    expect(next.invitation.expiresAt, deadline);
    expect(original.closed, isTrue);
  });

  test('到期后同一 Wi-Fi 的状态刷新不会反复续期，重新进入网络才开始新窗口', () async {
    await service.updateEnvironment(_environment('Office'));
    final original = service.hosts.single;
    clock = clock.add(const Duration(minutes: 31));
    await original.close();
    await service.updateEnvironment(_environment('Office'));
    await service.updateEnvironment(_environment('Office'));
    expect(service.hosts, isEmpty);
    expect(service.hasExpiredWindow(profile.id), isTrue);
    await service.updateEnvironment(_environment(null));
    await service.updateEnvironment(_environment('Office'));
    expect(
      service.hosts.single.invitation.expiresAt,
      clock.add(const Duration(minutes: 30)),
    );
  });

  test('手动停止会持久暂停自动规则，刷新和离开再进入均不会重开', () async {
    await service.updateEnvironment(_environment('Office'));
    await service.stopShare(profile.id);
    await service.updateEnvironment(_environment('Office'));
    await service.updateEnvironment(_environment('Home'));
    await service.updateEnvironment(_environment('Office'));
    expect(service.hosts, isEmpty);
    expect(store.value.profiles.single.automaticallyPrepares, isFalse);
  });

  test('重启服务恢复自动规则但不恢复过时 transport 或旧监听端口', () async {
    await service.updateEnvironment(_environment('Office'));
    final previous = service.hosts.single;
    await service.dispose();
    service = DeviceShareService(
      adb,
      store: store,
      backendFactory: (_, _) => source.backend,
    );
    await service.initialize();
    await service.updateEnvironment(_environment('Office'));
    final current = service.hosts.single;
    expect(previous.closed, isTrue);
    expect(current.invitation.fingerprint, previous.invitation.fingerprint);
    expect(current.invitation.token, previous.invitation.token);
  });

  test('永久规则没有会话到期时间', () async {
    await service.dispose();
    store.value = DeviceShareSavedState(
      profiles: [profile.copyWith(lifetime: DeviceShareLifetime.unlimited)],
    );
    service = DeviceShareService(
      adb,
      store: store,
      backendFactory: (_, _) => source.backend,
    );
    await service.initialize();
    await service.updateEnvironment(_environment('Office'));
    expect(service.hosts.single.invitation.expiresAt, isNull);
  });

  test('读取不到真实 Wi-Fi 时不能用展示用扫描猜测值触发自动共享', () async {
    await service.updateEnvironment(_environment('Office', verified: false));
    expect(service.hosts, isEmpty);
    expect(source.requests, isEmpty);
  });

  test('共享来源、其他手机和非 Android 设备不能代替原手机自动开启', () async {
    for (final device in const [
      DiscoveredDevice(id: 'other', status: 'device', transportId: '72'),
      DiscoveredDevice(
        id: 'phone',
        status: 'device',
        transportId: '72',
        product: 'anydeck_shared_device',
      ),
      DiscoveredDevice(
        id: 'phone',
        status: 'device',
        transportId: '72',
        isIos: true,
      ),
      DiscoveredDevice(
        id: 'phone',
        status: 'device',
        transportId: '72',
        isHarmony: true,
      ),
    ]) {
      await service.updateEnvironment(
        _environment('Office', devices: [device]),
      );
      expect(service.hosts, isEmpty);
    }
  });

  test('建立共享期间切网会关闭迟到会话', () async {
    await service.dispose();
    final opening = Completer<void>(), gate = Completer<void>();
    service = DeviceShareService(
      adb,
      store: store,
      backendFactory: (_, _) =>
          _DelayedBackend(source.server.port, opening, gate),
    );
    await service.initialize();
    final starting = service.updateEnvironment(_environment('Office'));
    await opening.future.timeout(const Duration(seconds: 2));
    final switched = service.updateEnvironment(_environment('Home'));
    gate.complete();
    await Future.wait([starting, switched]);
    expect(service.hosts, isEmpty);
  });

  test('自动握手期间点击停止会排队完成，不会被 busy 丢弃', () async {
    await service.dispose();
    final opening = Completer<void>(), gate = Completer<void>();
    service = DeviceShareService(
      adb,
      store: store,
      backendFactory: (_, _) =>
          _DelayedBackend(source.server.port, opening, gate),
    );
    await service.initialize();
    final starting = service.updateEnvironment(_environment('Office'));
    await opening.future.timeout(const Duration(seconds: 2));
    final stopping = service.stopShare(profile.id);
    gate.complete();
    await Future.wait([starting, stopping]);
    expect(service.hosts, isEmpty);
    expect(store.value.profiles.single.automaticallyPrepares, isFalse);
  });
}
