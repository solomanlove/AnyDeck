import 'dart:async';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_info_service.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/mirror_stream_health.dart';
import 'package:any_deck/core/scrcpy/mirror_transport_devices_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mirror_transport_fakes.dart';

const _shared = '127.0.0.1:5559';
const _online = DiscoveredDevice(id: _shared, status: 'device');

/// 用传输失败触发真实 DeviceInfoService 的成功缓存回退，不运行外部命令。
class _FailingAdb extends AdbService {
  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async => const AdbResult(exitCode: 124, stdout: '', stderr: 'timeout');
}

/// 只统计概览采集次数；磁盘与设备由内存快照替代，失败时复用真实回退逻辑。
class _CountingInfo extends DeviceInfoService {
  _CountingInfo() : super(_FailingAdb());

  int loads = 0;
  bool failNext = false;
  DeviceOverview? cached;

  @override
  Future<DeviceOverview?> loadFromCache(String deviceId) async => cached;

  @override
  Future<DeviceOverview> loadOverview(
    String deviceId, {
    String? androidVersion,
    bool allowCachedFallback = true,
  }) async {
    loads++;
    if (failNext) {
      failNext = false;
      return super.loadOverview(
        deviceId,
        androidVersion: androidVersion,
        allowCachedFallback: allowCachedFallback,
      );
    }
    return cached = DeviceOverview.fromJson({
      'name': 'snapshot-$loads',
      'memory': '8 GB',
    });
  }
}

/// 不读取用户设备历史，隔离概览以外的元数据刷新。
class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => const [];
}

void main() {
  late _CountingInfo info;
  late TransportMirrors mirrors;
  late ProviderContainer container;
  late StreamController<List<DiscoveredDevice>> transportEvents;

  setUp(() {
    info = _CountingInfo();
    mirrors = TransportMirrors();
    transportEvents = StreamController<List<DiscoveredDevice>>.broadcast();
    container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('mirror-test'),
        adbServiceProvider.overrideWithValue(TransportAdb()),
        embeddedScrcpyServiceProvider.overrideWithValue(mirrors),
        deviceInfoServiceProvider.overrideWithValue(info),
        deviceRegistryProvider.overrideWith(_Registry.new),
        deviceAndroidVersionProvider.overrideWith((ref, deviceId) => null),
        mirrorTransportDevicesProvider.overrideWith(
          (ref) => transportEvents.stream,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await transportEvents.close();
  });

  Future<void> watchOverview(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, child) {
            ref.watch(deviceOverviewProvider(_shared));
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    await container.read(deviceOverviewProvider(_shared).future);
  }

  Future<void> publish(
    WidgetTester tester,
    List<DiscoveredDevice> devices,
  ) async {
    transportEvents.add(devices);
    await tester.pump();
    await tester.pump();
    await container.read(deviceOverviewProvider(_shared).future);
  }

  Future<void> startAndRead(WidgetTester tester) async {
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .toggleMirroring();
    await watchOverview(tester);
    await publish(tester, [_online]);
    expect(info.loads, 1);
    expect(
      container.read(deviceOverviewProvider(_shared)).value?.name,
      'snapshot-1',
    );
  }

  testWidgets('子窗口等待真实 ADB 快照，初始空列表不会提前或重复采集概览', (tester) async {
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .toggleMirroring();
    await watchOverview(tester);
    expect(info.loads, 0);
    await publish(tester, []);
    expect(info.loads, 0);
    await publish(tester, [_online]);
    expect(info.loads, 1);
    await publish(tester, [_online]);
    expect(info.loads, 1);
    await publish(tester, [
      _online,
      const DiscoveredDevice(id: 'other-phone', status: 'device'),
    ]);
    expect(info.loads, 1);
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .forceStop();
  });

  testWidgets('真实概览 Provider 不因健康降档替换 Texture 重复查询硬件', (tester) async {
    await startAndRead(tester);
    final gate = Completer<void>();
    mirrors.stopGates[_shared] = gate;
    mirrors.health[_shared] = const MirrorStreamHealth(videoLagMs: 500);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(container.read(activeEmbeddedMirrorProvider(_shared)), isNull);
    expect(
      container.read(deviceOverviewProvider(_shared)).value?.name,
      'snapshot-1',
    );
    expect(info.loads, 1);

    gate.complete();
    await tester.pump();
    await tester.pump();
    await container.read(deviceOverviewProvider(_shared).future);
    expect(mirrors.starts, hasLength(2));
    expect(container.read(activeEmbeddedMirrorProvider(_shared)), isNotNull);
    expect(info.loads, 1);
    expect(
      container.read(deviceOverviewProvider(_shared)).value?.name,
      'snapshot-1',
    );
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .forceStop();
  });

  testWidgets('真实 ADB 离线保留成功缓存，再次上线重新采集概览', (tester) async {
    await startAndRead(tester);
    await publish(tester, []);
    expect(info.loads, 1);
    expect(
      container.read(deviceOverviewProvider(_shared)).value?.name,
      'snapshot-1',
    );
    await publish(tester, [_online]);
    expect(info.loads, 2);
    expect(
      container.read(deviceOverviewProvider(_shared)).value?.name,
      'snapshot-2',
    );
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .forceStop();
  });

  testWidgets('在线时显式刷新仍重新采集并展示最新概览', (tester) async {
    await startAndRead(tester);
    container.invalidate(deviceOverviewProvider(_shared));
    await tester.pump();
    await tester.pump();
    expect(info.loads, 2);
    expect(
      container.read(deviceOverviewProvider(_shared)).value?.name,
      'snapshot-2',
    );
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .forceStop();
  });

  testWidgets('显式刷新遇到传输失败仍沿用完整成功缓存', (tester) async {
    await startAndRead(tester);
    info.failNext = true;
    container.invalidate(deviceOverviewProvider(_shared));
    await tester.pump();
    await tester.pump();
    expect(info.loads, 2);
    final overview = container.read(deviceOverviewProvider(_shared));
    expect(overview.hasError, isFalse);
    expect(overview.value?.name, 'snapshot-1');
    expect(overview.value?.memory, '8 GB');
    await container
        .read(activeEmbeddedMirrorProvider(_shared).notifier)
        .forceStop();
  });

  testWidgets('主窗口继续使用设备发现在线状态，不订阅投屏专用 Tracker', (tester) async {
    container.dispose();
    var transportSubscriptions = 0;
    container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue(''),
        deviceInfoServiceProvider.overrideWithValue(info),
        deviceRegistryProvider.overrideWith(_Registry.new),
        deviceAndroidVersionProvider.overrideWith((ref, deviceId) => null),
        discoveredDevicesProvider.overrideWith((ref) => transportEvents.stream),
        mirrorTransportDevicesProvider.overrideWith((ref) {
          transportSubscriptions++;
          return const Stream.empty();
        }),
      ],
    );
    await watchOverview(tester);
    await publish(tester, [_online]);
    expect(info.loads, 1);
    await publish(tester, []);
    await publish(tester, [_online]);
    expect(info.loads, 2);
    expect(transportSubscriptions, 0);
  });
}
