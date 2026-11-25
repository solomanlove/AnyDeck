import 'dart:async';
import 'dart:convert';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/emulator/emulator_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

const _ports = [
  'emulator-5556',
  'emulator-5600',
  'emulator-5562',
  'emulator-5572',
];
const _product = 'sdk_gphone16k_arm64';

/// 用实际注册表入口复现旧端口缓存、切换端口及两个同型号 AVD。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧记录唯一匹配时合并并保留四个端口，两个匹配时分别展示', () async {
    for (final avds in [
      [_avd('Api36_16KB'), _avd('Api36_4KB', page16k: false)],
      [_avd('Api36_16KB'), _avd('Another_16KB')],
    ]) {
      SharedPreferences.setMockInitialValues({
        'devices.history': _ports,
        'devices.products': jsonEncode({for (final id in _ports) id: _product}),
        'devices.models': jsonEncode({for (final id in _ports) id: _product}),
        'devices.sdkVersions': jsonEncode({for (final id in _ports) id: 36}),
        for (final id in _ports)
          'devices.overview.$id': jsonEncode({'serial': 'EMULATOR37X3X9X0'}),
      });
      final harness = _Registry(avds);
      try {
        await pumpEventQueue();
        final devices = harness.devices;
        if (avds.last.name == 'Api36_4KB') {
          expect(devices.single.emulatorAvdName, 'Api36_16KB');
          expect(devices.single.connectionHistory, [
            for (final port in _ports)
              (id: port, connectedAt: null, disconnectedAt: null),
          ]);
          expect(devices.single.isOnline, isFalse);
        } else {
          expect(devices, hasLength(4));
          expect(
            devices.every((device) => device.connectionHistory.length == 1),
            isTrue,
          );
        }
      } finally {
        await harness.dispose();
      }
    }
  });

  test('换端口后按 AVD 合并，命令只使用在线端口，编辑和历史保留', () async {
    SharedPreferences.setMockInitialValues({});
    final harness = _Registry([]);
    addTearDown(harness.dispose);
    await harness.connect(_ports[0], 'Primary', '1');
    await harness.container
        .read(deviceRegistryProvider.notifier)
        .setAlias(_ports[0], '测试机');
    await harness.connect(_ports[1], 'Primary', '2');

    final device = harness.devices.single;
    expect(device.emulatorAvdName, 'Primary');
    expect(device.displayName, '测试机');
    expect(device.connectionHistory.map((entry) => entry.id), [
      _ports[0],
      _ports[1],
    ]);
    expect(
      device.connectionHistory.every((entry) => entry.connectedAt != null),
      isTrue,
    );
    expect(device.connectionHistory.first.disconnectedAt, isNotNull);
    expect(device.connectionHistory.last.disconnectedAt, isNull);
    expect(device.connections, [_ports[1]]);
    expect(device.preferredCommandId, _ports[1]);
    expect(harness.adb.probes, 2);

    final reloaded = _Registry([]);
    addTearDown(reloaded.dispose);
    await pumpEventQueue();
    expect(reloaded.devices.single.connectionHistory, device.connectionHistory);
    expect(reloaded.devices.single.displayName, '测试机');
  });

  test('端口被不同 AVD 复用时保留旧记录且别名不会串到新设备', () async {
    SharedPreferences.setMockInitialValues({});
    final harness = _Registry([]);
    addTearDown(harness.dispose);
    final port = _ports.first;
    await harness.connect(port, 'Primary', '1');
    final previousConnection = harness.devices.single.connectionHistory.single;
    await harness.container
        .read(deviceRegistryProvider.notifier)
        .setAlias(port, '旧设备');
    await harness.connect(port, 'Secondary', '2');
    final old = harness.devices.singleWhere(
      (d) => d.emulatorAvdName == 'Primary',
    );
    final current = harness.devices.singleWhere(
      (d) => d.emulatorAvdName == 'Secondary',
    );
    expect(old.isOnline, isFalse);
    expect(old.displayName, '旧设备');
    final closedConnection = old.connectionHistory.single;
    expect(closedConnection.id, previousConnection.id);
    expect(closedConnection.connectedAt, previousConnection.connectedAt);
    expect(
      closedConnection.disconnectedAt,
      current.connectionHistory.single.connectedAt,
    );
    expect(current.connectionHistory.single.id, port);
    expect(current.connectionHistory.single.connectedAt, isNotNull);
    expect(current.connectionHistory.single.disconnectedAt, isNull);
    expect(current.customName, isNull);
    expect(current.isOnline, isTrue);
    expect(current.preferredCommandId, port);

    await harness.container
        .read(deviceRegistryProvider.notifier)
        .removeDevice(old.id);
    expect(harness.devices.single.emulatorAvdName, 'Secondary');
  });

  test('起止时间兼容旧缓存并按连接状态更新，结束后可重载', () async {
    final previous = DateTime.utc(2025, 1, 1, 10);
    final port = _ports[0];
    SharedPreferences.setMockInitialValues({
      'devices.history': _ports.take(3).toList(),
      'devices.emulatorConnections.v1': [
        jsonEncode(['Primary', _ports[1]]),
        jsonEncode(['Primary', _ports[2], 'invalid']),
        jsonEncode(['Primary', port, previous.toIso8601String()]),
      ],
    });
    final harness = _Registry([]);
    addTearDown(harness.dispose);
    await pumpEventQueue();
    expect(harness.devices.single.connectionHistory, [
      (id: _ports[1], connectedAt: null, disconnectedAt: null),
      (id: _ports[2], connectedAt: null, disconnectedAt: null),
      (id: port, connectedAt: previous, disconnectedAt: null),
    ]);

    await harness.connect(port, 'Primary', '1', status: 'unauthorized');
    expect(harness.devices.single.connectionHistory.last.connectedAt, previous);
    expect(
      harness.devices.single.connectionHistory.last.disconnectedAt,
      isNull,
    );

    final before = DateTime.now().toUtc();
    await harness.connect(port, 'Primary', '1');
    final newTime = harness.devices.single.connectionHistory.last.connectedAt!;
    expect(newTime.isBefore(before), isFalse);
    expect(newTime.isAfter(DateTime.now().toUtc()), isFalse);

    await harness.connect(port, 'Primary', '1');
    expect(harness.devices.single.connectionHistory.last.connectedAt, newTime);
    expect(
      harness.devices.single.connectionHistory.last.disconnectedAt,
      isNull,
    );

    final beforeDisconnect = DateTime.now().toUtc();
    await harness.connect(port, 'Primary', '1', status: 'offline');
    final stopped = harness.devices.single.connectionHistory.last;
    final end = stopped.disconnectedAt!;
    expect(stopped.connectedAt, newTime);
    expect(end.isBefore(beforeDisconnect), isFalse);
    expect(end.isAfter(DateTime.now().toUtc()), isFalse);
    await harness.connect(port, 'Primary', '1', status: 'offline');
    expect(harness.devices.single.connectionHistory.last, stopped);

    final stored = await SharedPreferences.getInstance();
    expect(
      stored.getStringList('devices.emulatorConnections.v1'),
      contains(
        jsonEncode([
          'Primary',
          port,
          newTime.toIso8601String(),
          end.toIso8601String(),
        ]),
      ),
    );
    final reloaded = _Registry([]);
    addTearDown(reloaded.dispose);
    await pumpEventQueue();
    expect(reloaded.devices.single.connectionHistory.last, stopped);

    await harness.connect(port, 'Primary', '2');
    final reconnected = harness.devices.single.connectionHistory.last;
    expect(reconnected.connectedAt!.isAfter(newTime), isTrue);
    expect(reconnected.disconnectedAt, isNull);
    await harness.disconnect();
    expect(
      harness.devices.single.connectionHistory.last.disconnectedAt,
      isNotNull,
    );
  });

  test('旧 transport 的迟到查询不会覆盖复用端口的新身份', () async {
    SharedPreferences.setMockInitialValues({});
    final harness = _Registry([]);
    addTearDown(harness.dispose);
    final delayed = Completer<AdbResult>();
    harness.adb.delayed = delayed;
    await harness.connect(_ports.first, 'Old', '1');
    await harness.connect(_ports.first, 'New', '2');
    delayed.complete(
      const AdbResult(exitCode: 0, stdout: 'Old\nOK\n', stderr: ''),
    );
    await pumpEventQueue();
    expect(harness.devices.single.emulatorAvdName, 'New');
  });
}

AndroidEmulator _avd(String name, {bool page16k = true}) => AndroidEmulator(
  name: name,
  sdkVersion: '36',
  abi: 'arm64-v8a',
  config: {'image.sysdir.1': page16k ? 'google_apis_ps16k' : 'google_apis'},
);

/// 隔离宿主配置和 ADB，保留 Riverpod、合并和 SharedPreferences 链路。
class _Registry {
  _Registry(List<AndroidEmulator> avds) {
    container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        emulatorServiceProvider.overrideWithValue(_Emulators(avds)),
        discoveredDevicesProvider.overrideWith((_) => stream.stream),
      ],
    );
    container.listen(deviceRegistryProvider, (_, _) {});
  }

  final stream = StreamController<List<DiscoveredDevice>>();
  final adb = _Adb();
  late final ProviderContainer container;

  List<RegisteredDevice> get devices => container.read(deviceRegistryProvider);

  Future<void> connect(
    String port,
    String avd,
    String transport, {
    String status = 'device',
  }) async {
    adb.names[port] = avd;
    stream.add([
      DiscoveredDevice(
        id: port,
        status: status,
        transportId: transport,
        model: _product,
        product: _product,
      ),
    ]);
    await pumpEventQueue();
  }

  Future<void> disconnect() async {
    stream.add(const []);
    await pumpEventQueue();
  }

  Future<void> dispose() async {
    container.dispose();
    await stream.close();
  }
}

class _Emulators extends EmulatorService {
  _Emulators(this.avds);

  final List<AndroidEmulator> avds;

  @override
  Future<List<AndroidEmulator>> listConfiguredEmulators() async => avds;
}

class _Adb extends FakeAdbService {
  final names = <String, String>{};
  Completer<AdbResult>? delayed;
  int probes = 0;

  @override
  Future<AdbResult> run(
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (args.length == 5 && args[2] == 'emu') {
      probes++;
      final pending = delayed;
      delayed = null;
      if (pending != null) return pending.future;
      return AdbResult(
        exitCode: 0,
        stdout: '${names[args[1]]}\nOK\n',
        stderr: '',
      );
    }
    return super.run(args, timeout: timeout);
  }
}
