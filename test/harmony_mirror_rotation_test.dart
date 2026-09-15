import 'dart:async';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/harmony/harmony_mirror_operations.dart';
import 'package:any_deck/core/harmony/harmony_mirror_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只模拟会话是否存在，确保子窗口的在线判定不依赖主窗口设备轮询。
class _HarmonyMirror extends ActiveHarmonyMirrorNotifier {
  _HarmonyMirror() : super('phone');
  @override
  int? build() => null;
  void update(int? texture) => state = texture;
}

class _IosMirror extends ActiveIosMirrorNotifier {
  _IosMirror() : super('phone');
  @override
  int? build() => null;
}

class _AndroidMirror extends ActiveEmbeddedMirrorNotifier {
  _AndroidMirror() : super('phone');
  @override
  int? build() => null;
}

void main() {
  test('鸿蒙子窗口启停会话能持续更新在线状态', () {
    final container = ProviderContainer(overrides: [
      windowIdProvider.overrideWithValue('mirror-test'),
      activeHarmonyMirrorProvider('phone').overrideWith(_HarmonyMirror.new),
      activeIosMirrorProvider('phone').overrideWith(_IosMirror.new),
      activeEmbeddedMirrorProvider('phone').overrideWith(_AndroidMirror.new),
    ]);
    addTearDown(container.dispose);
    final subscription = container.listen(deviceOnlineProvider('phone'), (_, _) {});
    addTearDown(subscription.close);
    final mirror = container.read(activeHarmonyMirrorProvider('phone').notifier)
        as _HarmonyMirror;
    expect(subscription.read(), isFalse);
    mirror.update(42);
    expect(subscription.read(), isTrue);
    mirror.update(null);
    expect(subscription.read(), isFalse);
    mirror.update(43);
    expect(subscription.read(), isTrue);
  });

  test('主屏 Bounds 优先于历史记录和投屏虚拟屏', () {
    for (final (width, height) in [(1224, 2776), (2776, 1224)]) {
      final dump = '''
[09-15 18:52:13]: screenId: 0 rotation: 0 width: 1224 height: 2776
---------------- Screen ID: 0 ----------------
[SCREEN INFO]
Orientation: 2
[SCREEN PROPERTY]
Bounds<L,T,W,H>: 0, 0, $width, $height,
PhyBounds<L,T,W,H>: 0, 0, 1224, 2776,
---------------- Screen ID: 1055 ----------------
Bounds<L,T,W,H>: 0, 0, 1224, 2776,
---------------- Display ID: 0 ----------------
Width: 1224
Height: 2776
---------------- Display ID: 1055 ----------------
Width: 1224
Height: 2776
''';
      expect(HarmonyMirrorService.parseDisplayDimensions(dump), (width, height));
    }
    expect(HarmonyMirrorService.parseDisplayDimensions('width: 0 height: 0'),
        (null, null));
  });

  test('并发启动与停止按设备排队，不阻塞另一台设备', () async {
    final operations = HarmonyMirrorOperations();
    final gate = Completer<void>();
    final events = <String>[];
    var active = false;
    Future<int> start() async {
      if (!active) {
        events.add('start');
        await gate.future;
        active = true;
      }
      return 42;
    }
    final first = operations.run('phone', start);
    final second = operations.run('phone', start);
    final stop = operations.run('phone', () async {
      events.add('stop');
      active = false;
    });
    expect(await operations.run('other', () async => 7), 7);
    expect(events, ['start']);
    gate.complete();
    expect(await first, 42);
    expect(await second, 42);
    await stop;
    expect(events, ['start', 'stop']);
    expect(active, isFalse);
  });

  test('启动失败后仍然执行停止与重试', () async {
    final operations = HarmonyMirrorOperations();
    final failed = operations.run<int>('phone', () async => throw StateError('failed'));
    final cleanup = operations.run('phone', () async => 'stopped');
    await expectLater(failed, throwsStateError);
    expect(await cleanup, 'stopped');
    expect(await operations.run('phone', () async => 43), 43);
  });
}
