import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
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
  setUp(() async {
    backend = ShareAdbFixture();
    await backend.start();
    adb = _Devices();
    service = DeviceShareService(
      adb,
      backendFactory: (_, _) => backend.backend,
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

  test('设备拔线或 transport 变化立即撤销已有共享，不自动替换设备', () async {
    final share = await service.share('phone', '测试手机', '127.0.0.1');
    service.validateHosts(const [
      DiscoveredDevice(id: 'phone', status: 'device', transportId: '99'),
    ]);
    await share.close();
    expect(share.closed, isTrue);
    expect(service.hosts, isEmpty);
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
    await expectLater(
      service.share('phone', '测试手机', '127.0.0.1'),
      throwsStateError,
    );
  });
}
