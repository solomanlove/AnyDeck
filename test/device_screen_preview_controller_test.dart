import 'dart:async';
import 'dart:typed_data';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/controller/device_screen_preview_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只替换平台截图边界，验证真实 Controller 的主动采集与异步生命周期。
void main() {
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
    await controller.capture();
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
  _PreviewFixture(List<RegisteredDevice> devices) {
    container = ProviderContainer(
      overrides: [
        deviceRegistryProvider.overrideWith(() => _MemoryRegistry(devices)),
        adbServiceProvider.overrideWithValue(_PreviewAdb(adb)),
        hdcServiceProvider.overrideWithValue(_PreviewHdc(hdc)),
        iosCommandServiceProvider.overrideWithValue(_PreviewIos(ios)),
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
}
