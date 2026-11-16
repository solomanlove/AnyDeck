import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/device_share/device_share_auto_prepare.dart';
import 'package:any_deck/core/device_share/device_share_models.dart';
import 'package:any_deck/core/device_share/device_share_store.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/device_share_fixture.dart';

class _Devices extends FakeAdbService {
  List<DiscoveredDevice> devices = const [
    DiscoveredDevice(id: 'phone', status: 'device', transportId: '72'),
  ];
  @override
  Future<List<DiscoveredDevice>> listDevices() async => devices;
}

void main() {
  late ShareAdbFixture backend;
  late _Devices adb;
  late DeviceShareService service;
  final diagnostics = <String>[];
  setUp(() async {
    diagnostics.clear();
    backend = ShareAdbFixture();
    await backend.start();
    adb = _Devices();
    service = DeviceShareService(
      adb,
      backendFactory: (_, _) => backend.backend,
      onDiagnostic: diagnostics.add,
    );
  });
  tearDown(() async {
    await service.dispose();
    await backend.close();
  });

  test('相同设备重复点击复用共享会话，不能连接自己的分享码', () async {
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    expect(await service.share('phone', '测试手机', '127.0.0.1'), same(share));
    expect(service.hosts, hasLength(1));
    await expectLater(
      service.join(share.invitation.encode()),
      throwsStateError,
    );
  });

  test('源设备 transport 变化立即撤销已有共享，不自动替换设备', () async {
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    service.validateHosts(const [
      DiscoveredDevice(id: 'phone', status: 'device', transportId: '99'),
    ]);
    await share.close();
    expect(share.closed, isTrue);
    expect(service.hosts, isEmpty);
    expect(diagnostics, contains(contains('reason=sourceTransportChanged')));
  });

  test('源设备缺失时撤销共享并记录 sourceUnavailable', () async {
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    service.validateHosts(const []);
    await share.close();
    expect(share.closed, isTrue);
    expect(diagnostics, contains(contains('reason=sourceUnavailable')));
  });

  test('网络或串号更新复用旧设备快照时，不撤销刚从实时 ADB 创建的共享', () async {
    const stale = DeviceShareEnvironment(
      network: HostNetworkInfo(),
      devices: [
        DiscoveredDevice(id: 'phone', status: 'device', transportId: '71'),
      ],
    );
    await service.updateEnvironment(stale);
    // share() 回读实时列表，实际绑定 72；元数据通知仍可能携带缓存的 71。
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    expect(share.backend.transportId, '72');
    await service.updateEnvironment(stale, sourceDevicesUpdated: false);
    expect(share.closed, isFalse);
    expect(diagnostics, isNot(contains(startsWith('host_stopped'))));
  });

  test('设备原 transport 保持在线时不打断共享，状态变化发出不同 revision', () async {
    final revisions = <int>[];
    final subscription = service.changes.listen(revisions.add);
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    service.validateHosts(adb.devices);
    expect(share.closed, isFalse);
    await share.close();
    await Future<void>.delayed(Duration.zero);
    expect(revisions.length, greaterThanOrEqualTo(2));
    expect(revisions.toSet().length, revisions.length);
    await subscription.cancel();
  });

  for (final device in const [
    DiscoveredDevice(id: 'phone', status: 'offline', transportId: '72'),
    DiscoveredDevice(id: 'phone', status: 'unauthorized', transportId: '72'),
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
    DiscoveredDevice(
      id: 'phone',
      status: 'device',
      transportId: '72',
      product: 'anydeck_shared_device',
    ),
    DiscoveredDevice(id: 'phone', status: 'device'),
  ]) {
    test(
      '拒绝离线、未授权、非 Android、共享来源及无 transport ID 的设备 ${device.status}/${device.product}/${device.isIos}/${device.isHarmony}/${device.transportId}',
      () async {
        adb.devices = [device];
        await expectLater(
          service.share('phone', '测试手机', '127.0.0.1'),
          throwsStateError,
        );
        expect(service.hosts, isEmpty);
        expect(backend.requests, isEmpty);
      },
    );
  }

  test('应用销毁会撤销所有会话，原服务不能再创建共享', () async {
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    await service.dispose();
    expect(share.closed, isTrue);
    expect(diagnostics, contains(contains('reason=appExit')));
    await expectLater(
      service.share('phone', '测试手机', '127.0.0.1'),
      throwsStateError,
    );
  });

  test('停止后保留可重启规则，删除后再创建则撤销旧身份', () async {
    final share = await service.share(
      'phone',
      '测试手机',
      '127.0.0.1',
      lifetime: DeviceShareLifetime.hour1,
    );
    final id = service.profiles.single.id;
    await service.stopShare(id);
    expect(share.closed, isTrue);
    expect(service.profiles.single.enabled, isFalse);
    final resumed = await service.resumeShare(id);
    expect(resumed.invitation.fingerprint, share.invitation.fingerprint);
    expect(resumed.invitation.token, share.invitation.token);
    await service.forgetShare(id);
    expect(service.profiles, isEmpty);
    final fresh = await service.share('phone', '测试手机', '127.0.0.1');
    expect(fresh.invitation.fingerprint, isNot(share.invitation.fingerprint));
    expect(fresh.invitation.token, isNot(share.invitation.token));
  });

  test('服务重启后手动规则仍可从新 transport 重新准备', () async {
    await service.dispose();
    final store = MemoryDeviceShareStore();
    service = DeviceShareService(
      adb,
      store: store,
      backendFactory: (_, _) => backend.backend,
    );
    final original = await service.share('phone', '测试手机', '127.0.0.1');
    final id = original.invitation.fingerprint;
    await service.dispose();
    backend.transportId = '99';
    adb.devices = const [
      DiscoveredDevice(id: 'phone', status: 'device', transportId: '99'),
    ];
    service = DeviceShareService(
      adb,
      store: store,
      backendFactory: (_, _) => backend.backend,
    );
    await service.initialize();
    final current = await service.resumeShare(id);
    expect(current.backend.transportId, '99');
    expect(current.invitation.fingerprint, id);
  });
}
