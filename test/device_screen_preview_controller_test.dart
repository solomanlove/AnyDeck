import 'dart:async';
import 'dart:typed_data';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/controller/device_screen_preview_controller.dart';
import 'package:any_deck/features/devices/widgets/device_screen_preview.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只替换平台截图边界，验证真实 Controller 的队列与异步生命周期。
void main() {
  testWidgets('虚拟墙仅为当前挂载卡片截图，滚动后更新新出现设备且不定时轮询', (tester) async {
    final fixture = _PreviewFixture([
      for (var i = 0; i < 30; i++) _device('device-$i'),
    ]);
    addTearDown(fixture.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: fixture.container,
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: ListView.builder(
                controller: scroll,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemExtent: 150,
                itemCount: 30,
                itemBuilder: (_, index) => DeviceScreenPreview(
                  key: ValueKey(index),
                  deviceId: 'device-$index',
                  online: true,
                  builder: (_, preview) =>
                      Text('${preview.value?.length ?? 0}'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fixture.adb.ids, ['device-0', 'device-1']);
    scroll.jumpTo(600);
    await tester.pumpAndSettle();
    expect(fixture.adb.ids, ['device-0', 'device-1', 'device-4', 'device-5']);
    await tester.pump(const Duration(minutes: 2));
    expect(fixture.adb.ids, hasLength(4));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('初始化与订阅不触发截图，未注册或离线设备拒绝采集', () async {
    final fixture = _PreviewFixture([
      _device('online'),
      _device('offline', online: false),
    ]);
    addTearDown(fixture.dispose);
    for (final id in ['online', 'offline', 'missing']) {
      final provider = deviceScreenPreviewProvider(id);
      fixture.container.listen(provider, (_, _) {});
      expect(await fixture.container.read(provider.future), isNull);
    }
    expect(fixture.adb.ids, isEmpty);
    expect(fixture.hdc.ids, isEmpty);
    expect(fixture.ios.ids, isEmpty);

    for (final id in ['offline', 'missing']) {
      await fixture.container
          .read(deviceScreenPreviewProvider(id).notifier)
          .capture();
      expect(
        fixture.container.read(deviceScreenPreviewProvider(id)).value,
        isNull,
      );
    }
    expect(fixture.adb.ids, isEmpty);
    expect(fixture.hdc.ids, isEmpty);
    expect(fixture.ios.ids, isEmpty);
  });

  test('Android、HarmonyOS、iOS 按设备身份路由到对应截图服务', () async {
    final fixture = _PreviewFixture([
      _device('android'),
      _device('harmony', harmony: true),
      _device('ios', ios: true),
    ]);
    addTearDown(fixture.dispose);
    final results = <String, List<int>>{};
    for (final id in ['android', 'harmony', 'ios']) {
      final provider = deviceScreenPreviewProvider(id);
      fixture.container.listen(provider, (_, _) {});
      await fixture.container.read(provider.notifier).capture();
      results[id] = fixture.container.read(provider).requireValue!;
    }
    expect(fixture.adb.ids, ['android']);
    expect(fixture.hdc.ids, ['harmony']);
    expect(fixture.ios.ids, ['ios']);
    expect(results, {
      'android': [1],
      'harmony': [2],
      'ios': [3],
    });
  });

  test('同设备采集中重复点击不启动第二个命令，其他设备可独立采集', () async {
    final fixture = _PreviewFixture([_device('first'), _device('second')]);
    addTearDown(fixture.dispose);
    final pending = Completer<Uint8List>();
    fixture.adb.response = (id) =>
        id == 'first' ? pending.future : Future.value(Uint8List.fromList([4]));
    for (final id in ['first', 'second']) {
      fixture.container.listen(deviceScreenPreviewProvider(id), (_, _) {});
    }
    final first = deviceScreenPreviewProvider('first');
    final controller = fixture.container.read(first.notifier);
    final capture = controller.capture();
    expect(fixture.container.read(first).isLoading, isTrue);
    expect(identical(controller.capture(), capture), isTrue);
    expect(fixture.adb.ids, ['first']);

    final second = deviceScreenPreviewProvider('second');
    await fixture.container.read(second.notifier).capture();
    expect(fixture.adb.ids, ['first', 'second']);
    expect(fixture.container.read(second).requireValue, [4]);
    pending.complete(Uint8List.fromList([5]));
    await capture;
    expect(fixture.container.read(first).requireValue, [5]);
  });

  test('截图异常进入错误状态，再次主动采集可恢复', () async {
    final fixture = _PreviewFixture([_device('android')]);
    addTearDown(fixture.dispose);
    final provider = deviceScreenPreviewProvider('android');
    fixture.container.listen(provider, (_, _) {});
    fixture.adb.response = (_) => Future.error(StateError('capture failed'));
    final controller = fixture.container.read(provider.notifier);
    await controller.capture();
    expect(fixture.container.read(provider).hasError, isTrue);
    expect(fixture.container.read(provider).error, isA<StateError>());

    fixture.adb.response = (_) => Future.value(Uint8List.fromList([8, 9]));
    await controller.capture();
    expect(fixture.container.read(provider).hasError, isFalse);
    expect(fixture.container.read(provider).requireValue, [8, 9]);
    expect(fixture.adb.ids, ['android', 'android']);
  });

  test('采集前重新核对在线状态，不沿用初始化时的在线记录', () async {
    final fixture = _PreviewFixture([_device('android')]);
    addTearDown(fixture.dispose);
    final provider = deviceScreenPreviewProvider('android');
    fixture.container.listen(provider, (_, _) {});
    final controller = fixture.container.read(provider.notifier);
    fixture.container.read(deviceRegistryProvider.notifier).state = [
      _device('android', online: false),
    ];
    await controller.capture();
    expect(fixture.adb.ids, isEmpty);
    expect(fixture.container.read(provider).value, isNull);
  });

  test('自动墙预览路由三平台，iOS 使用禁止镜像挂载的专用入口', () async {
    final fixture = _PreviewFixture([
      _device('android'),
      _device('harmony', harmony: true),
      _device('ios', ios: true),
    ]);
    addTearDown(fixture.dispose);
    for (final id in ['android', 'harmony', 'ios']) {
      fixture.container.listen(deviceScreenPreviewProvider(id), (_, _) {});
      fixture.container
          .read(deviceScreenPreviewProvider(id).notifier)
          .setVisible(true);
    }
    await Future<void>.delayed(Duration.zero);
    expect(fixture.adb.ids, ['android']);
    expect(fixture.hdc.ids, ['harmony']);
    expect(fixture.ios.ids, ['ios']);
    expect(fixture.ios.previewIds, ['ios']);
  });

  test('整墙最多两个截图，未开始的隐藏或离线卡片不启动命令', () async {
    final fixture = _PreviewFixture([
      for (final id in ['first', 'second', 'hidden', 'offline', 'last'])
        _device(id),
    ]);
    addTearDown(fixture.dispose);
    final gates = <String, Completer<Uint8List>>{};
    fixture.adb.response = (id) => (gates[id] = Completer()).future;
    for (final device in fixture.container.read(deviceRegistryProvider)) {
      fixture.container.listen(
        deviceScreenPreviewProvider(device.id),
        (_, _) {},
      );
      fixture.container
          .read(deviceScreenPreviewProvider(device.id).notifier)
          .setVisible(true);
    }
    expect(fixture.adb.ids, ['first', 'second']);
    fixture.container
        .read(deviceScreenPreviewProvider('hidden').notifier)
        .setVisible(false);
    fixture.container.read(deviceRegistryProvider.notifier).state = [
      for (final device in fixture.container.read(deviceRegistryProvider))
        if (device.id == 'offline')
          device.copyWith(isOnline: false)
        else
          device,
    ];
    gates['first']!.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.adb.ids, ['first', 'second', 'last']);
    gates['second']!.complete(Uint8List.fromList([2]));
    gates['last']!.complete(Uint8List.fromList([3]));
    await Future<void>.delayed(Duration.zero);
    expect(
      fixture.container.read(deviceScreenPreviewProvider('hidden')).value,
      isNull,
    );
    expect(
      fixture.container.read(deviceScreenPreviewProvider('offline')).value,
      isNull,
    );
  });

  test('离墙丢弃旧结果，返回及连续刷新只在进行中的截图后补一轮', () async {
    final fixture = _PreviewFixture([_device('android')]);
    addTearDown(fixture.dispose);
    final gates = <Completer<Uint8List>>[];
    fixture.adb.response = (_) {
      final gate = Completer<Uint8List>();
      gates.add(gate);
      return gate.future;
    };
    final provider = deviceScreenPreviewProvider('android');
    fixture.container.listen(provider, (_, _) {});
    final controller = fixture.container.read(provider.notifier);
    controller.setVisible(true);
    controller.setVisible(false);
    controller.refreshIfVisible();
    expect(fixture.adb.ids, ['android']);
    controller.setVisible(true);
    controller.refreshIfVisible();
    controller.refreshIfVisible();
    gates.first.complete(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.adb.ids, ['android', 'android']);
    expect(fixture.container.read(provider).value, isNull);
    gates.last.complete(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.container.read(provider).requireValue, [2]);
  });

  test('UI 超时保留真实截图槽，平台结束前不叠加第三个 CLI', () {
    fakeAsync((async) {
      final fixture = _PreviewFixture([
        _device('first'),
        _device('second'),
        _device('third'),
      ], timeout: const Duration(seconds: 1));
      final gates = <String, Completer<Uint8List>>{};
      fixture.adb.response = (id) => (gates[id] = Completer()).future;
      for (final id in ['first', 'second', 'third']) {
        fixture.container.listen(deviceScreenPreviewProvider(id), (_, _) {});
        fixture.container
            .read(deviceScreenPreviewProvider(id).notifier)
            .setVisible(true);
      }
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      expect(
        fixture.container.read(deviceScreenPreviewProvider('first')).error,
        isA<TimeoutException>(),
      );
      expect(fixture.adb.ids, ['first', 'second']);
      gates['first']!.complete(Uint8List.fromList([1]));
      async.flushMicrotasks();
      expect(fixture.adb.ids, ['first', 'second', 'third']);
      expect(
        fixture.container.read(deviceScreenPreviewProvider('first')).hasError,
        isTrue,
      );
      gates['second']!.complete(Uint8List.fromList([2]));
      gates['third']!.complete(Uint8List.fromList([3]));
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 2));
      expect(fixture.adb.ids, ['first', 'second', 'third']);
      fixture.dispose();
    });
  });

  test('销毁立即清除 UI 超时计时器，不等待真实命令完成', () {
    fakeAsync((async) {
      final fixture = _PreviewFixture([_device('android')]);
      final command = Completer<Uint8List>();
      fixture.adb.response = (_) => command.future;
      final provider = deviceScreenPreviewProvider('android');
      fixture.container.listen(provider, (_, _) {});
      final capture = fixture.container.read(provider.notifier).capture();
      expect(async.nonPeriodicTimerCount, greaterThan(0));
      fixture.dispose();
      async.flushMicrotasks();
      expect(async.nonPeriodicTimerCount, 0);
      command.complete(Uint8List.fromList([1]));
      async.flushMicrotasks();
      var completed = false;
      capture.then((_) => completed = true);
      async.flushMicrotasks();
      expect(completed, isTrue);
    });
  });

  test('采集期间离线不发布旧截图，重新上线可以恢复', () async {
    final fixture = _PreviewFixture([_device('android')]);
    addTearDown(fixture.dispose);
    final pending = Completer<Uint8List>();
    fixture.adb.response = (_) => pending.future;
    final provider = deviceScreenPreviewProvider('android');
    fixture.container.listen(provider, (_, _) {});
    final controller = fixture.container.read(provider.notifier);
    final capture = controller.capture();
    fixture.container.read(deviceRegistryProvider.notifier).state = [
      _device('android', online: false),
    ];
    pending.complete(Uint8List.fromList([1]));
    await capture;
    expect(fixture.container.read(provider).value, isNull);
    fixture.container.read(deviceRegistryProvider.notifier).state = [
      _device('android'),
    ];
    fixture.adb.response = (_) async => Uint8List.fromList([2]);
    await controller.capture();
    expect(fixture.container.read(provider).requireValue, [2]);
  });

  for (final completeWithError in [false, true]) {
    test('销毁后${completeWithError ? '失败' : '成功'}的异步截图不再发布状态', () async {
      final fixture = _PreviewFixture([_device('android')]);
      addTearDown(fixture.dispose);
      final pending = Completer<Uint8List>();
      fixture.adb.response = (_) => pending.future;
      final events = <AsyncValue<Uint8List?>>[];
      final provider = deviceScreenPreviewProvider('android');
      fixture.container.listen(provider, (_, next) => events.add(next));
      final capture = fixture.container.read(provider.notifier).capture();
      expect(fixture.adb.ids, ['android']);
      fixture.dispose();
      final eventCount = events.length;
      if (completeWithError) {
        pending.completeError(StateError('completed after disposal'));
      } else {
        pending.complete(Uint8List.fromList([6]));
      }
      await expectLater(capture, completes);
      expect(events.length, eventCount);
    });
  }
}

RegisteredDevice _device(
  String id, {
  bool online = true,
  bool harmony = false,
  bool ios = false,
}) => RegisteredDevice(
  id: id,
  status: online ? 'device' : 'offline',
  isOnline: online,
  isHarmony: harmony,
  isIos: ios,
);

class _PreviewFixture {
  _PreviewFixture(List<RegisteredDevice> devices, {Duration? timeout}) {
    container = ProviderContainer(
      overrides: [
        deviceRegistryProvider.overrideWith(() => _MemoryRegistry(devices)),
        adbServiceProvider.overrideWithValue(_PreviewAdb(adb)),
        hdcServiceProvider.overrideWithValue(_PreviewHdc(hdc)),
        iosCommandServiceProvider.overrideWithValue(_PreviewIos(ios)),
        if (timeout != null)
          deviceScreenPreviewTimeoutProvider.overrideWithValue(timeout),
      ],
    );
  }

  final adb = _CaptureProbe(1);
  final hdc = _CaptureProbe(2);
  final ios = _CaptureProbe(3);
  late final ProviderContainer container;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
  }
}

/// 隔离历史存储和设备发现，测试只关注宿主提供的注册表快照。
class _MemoryRegistry extends DeviceRegistryNotifier {
  _MemoryRegistry(this.devices);
  final List<RegisteredDevice> devices;
  @override
  List<RegisteredDevice> build() => devices;
}

class _CaptureProbe {
  _CaptureProbe(this.value);
  final int value;
  final ids = <String>[];
  final previewIds = <String>[];
  Future<Uint8List> Function(String)? response;

  Future<Uint8List> capture(String id) {
    ids.add(id);
    return response?.call(id) ?? Future.value(Uint8List.fromList([value]));
  }
}

class _PreviewAdb extends AdbService {
  _PreviewAdb(this.probe);
  final _CaptureProbe probe;
  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) => probe.capture(deviceId);
}

class _PreviewHdc extends HdcService {
  _PreviewHdc(this.probe);
  final _CaptureProbe probe;
  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) => probe.capture(deviceId);
}

class _PreviewIos extends IosCommandService {
  _PreviewIos(this.probe);
  final _CaptureProbe probe;
  @override
  Future<Uint8List> captureScreenshot(String udid) => probe.capture(udid);
  @override
  Future<Uint8List> capturePreviewScreenshot(String udid) {
    probe.previewIds.add(udid);
    return probe.capture(udid);
  }
}
