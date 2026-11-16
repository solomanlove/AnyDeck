import 'dart:async';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/foldable/foldable_screen_controller.dart';
import 'package:any_deck/core/foldable/foldable_screen_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/screen_record_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _capability = FoldableScreenCapability(
  innerStateId: 3,
  outerStateId: 0,
  innerPhysicalId: 'inner',
  outerPhysicalId: 'outer',
);

FoldableScreenSnapshot _snapshot({bool outer = false, bool manual = false}) =>
    FoldableScreenSnapshot(
      capability: _capability,
      currentScreen: outer ? FoldableScreen.outer : FoldableScreen.inner,
      committedStateId: outer ? 0 : 3,
      overrideStateId: manual ? (outer ? 0 : 3) : null,
      hasOverride: manual,
    );

class _Service extends FoldableScreenService {
  _Service() : super(AdbService(executable: 'unused'), 'device');
  FoldableScreenSnapshot? snapshot = _snapshot();
  Completer<FoldableScreenSnapshot>? blocked;
  FoldableScreenError? failure;
  int refreshes = 0;
  int selections = 0;
  int releases = 0;
  bool owned = false;
  @override
  bool get ownsOverride => owned;
  @override
  Future<FoldableScreenSnapshot?> refresh({bool readDisplay = false}) async {
    refreshes++;
    return snapshot;
  }

  @override
  Future<FoldableScreenSnapshot> select(FoldableScreen screen) async {
    selections++;
    if (failure != null) throw failure!;
    if (blocked != null) return blocked!.future;
    owned = true;
    return snapshot = _snapshot(
      outer: screen == FoldableScreen.outer,
      manual: true,
    );
  }

  @override
  Future<FoldableScreenSnapshot> restoreAutomatic() async {
    owned = false;
    return snapshot = _snapshot();
  }

  @override
  Future<void> release() async {
    releases++;
    owned = false;
  }
}

class _Mirror extends ActiveEmbeddedMirrorNotifier {
  _Mirror() : super('device');
  @override
  int? build() => 1;
  void change(int? texture) => state = texture;
}

class _Power extends ScreenPowerOffNotifier {
  _Power() : super('device');
  @override
  bool build() => false;
  @override
  void setOff(bool value) => state = value;
}

class _Record extends ScreenRecordNotifier {
  _Record() : super('device');
  bool recording = false;
  @override
  ScreenRecordState build() =>
      ScreenRecordState(isRecording: recording, durationSeconds: 0);
}

ProviderContainer _container(
  _Service service, {
  _Power? power,
  _Record? record,
}) => ProviderContainer(
  overrides: [
    foldableScreenServiceProvider('device').overrideWithValue(service),
    activeEmbeddedMirrorProvider('device').overrideWith(_Mirror.new),
    screenPowerOffProvider('device').overrideWith(() => power ?? _Power()),
    screenRecordProvider('device').overrideWith(() => record ?? _Record()),
  ],
);

void main() {
  test('默认自动，按实际屏幕反向切换，长按恢复自动', () async {
    final service = _Service();
    final container = _container(service);
    addTearDown(container.dispose);
    container.listen(foldableScreenProvider('device'), (_, _) {});
    await container.pump();
    final controller = container.read(
      foldableScreenProvider('device').notifier,
    );
    expect(
      container.read(foldableScreenProvider('device')).mode,
      FoldableScreenMode.automatic,
    );
    expect(await controller.toggle(), isNull);
    expect(
      container.read(foldableScreenProvider('device')).mode,
      FoldableScreenMode.outer,
    );
    expect(await controller.toggle(), isNull);
    expect(
      container.read(foldableScreenProvider('device')).mode,
      FoldableScreenMode.inner,
    );
    expect(await controller.restoreAutomatic(), isNull);
    expect(
      container.read(foldableScreenProvider('device')).mode,
      FoldableScreenMode.automatic,
    );
  });

  test('正在切换时不重复发起请求，失败保留入口供重试', () async {
    final service = _Service()..blocked = Completer<FoldableScreenSnapshot>();
    final container = _container(service);
    addTearDown(container.dispose);
    container.listen(foldableScreenProvider('device'), (_, _) {});
    await container.pump();
    final controller = container.read(
      foldableScreenProvider('device').notifier,
    );
    final pending = controller.toggle();
    await container.pump();
    expect(container.read(foldableScreenProvider('device')).isBusy, isTrue);
    await controller.toggle();
    expect(service.selections, 1);
    service.blocked!.completeError(FoldableScreenError.timeout);
    expect(await pending, FoldableScreenError.timeout);
    expect(
      container.read(foldableScreenProvider('device')).snapshot,
      isNotNull,
    );
    expect(container.read(foldableScreenProvider('device')).isBusy, isFalse);
  });

  test('录屏或息屏时拒绝请求', () async {
    for (final recording in [false, true]) {
      final service = _Service();
      final power = _Power();
      final container = _container(
        service,
        power: power,
        record: _Record()..recording = recording,
      );
      container.listen(foldableScreenProvider('device'), (_, _) {});
      await container.pump();
      if (!recording) {
        container.read(screenPowerOffProvider('device').notifier).setOff(true);
      }
      expect(
        await container
            .read(foldableScreenProvider('device').notifier)
            .toggle(),
        recording
            ? FoldableScreenError.recording
            : FoldableScreenError.screenOff,
      );
      expect(service.selections, 0);
      container.dispose();
    }
  });

  test('设备明确不支持控制时隐藏入口', () async {
    final service = _Service()..failure = FoldableScreenError.unsupported;
    final container = _container(service);
    addTearDown(container.dispose);
    container.listen(foldableScreenProvider('device'), (_, _) {});
    await container.pump();
    expect(
      await container.read(foldableScreenProvider('device').notifier).toggle(),
      FoldableScreenError.unsupported,
    );
    expect(container.read(foldableScreenProvider('device')).snapshot, isNull);
  });

  test('断线释放请求，恢复后重新启动状态轮询', () {
    fakeAsync((time) {
      final service = _Service();
      final container = _container(service);
      container.listen(foldableScreenProvider('device'), (_, _) {});
      time.flushMicrotasks();
      final mirror =
          container.read(activeEmbeddedMirrorProvider('device').notifier)
              as _Mirror;
      mirror.change(null);
      time.flushMicrotasks();
      expect(service.releases, 1);
      mirror.change(2);
      time.flushMicrotasks();
      final refreshed = service.refreshes;
      time.elapse(const Duration(seconds: 3));
      time.flushMicrotasks();
      expect(service.refreshes, greaterThan(refreshed));
      container.dispose();
      time.flushMicrotasks();
    });
  });

  test('停止投屏后丢弃迟到的切换结果', () async {
    final service = _Service()..blocked = Completer<FoldableScreenSnapshot>();
    final container = _container(service);
    addTearDown(container.dispose);
    container.listen(foldableScreenProvider('device'), (_, _) {});
    await container.pump();
    final pending = container
        .read(foldableScreenProvider('device').notifier)
        .toggle();
    await container.pump();
    (container.read(activeEmbeddedMirrorProvider('device').notifier) as _Mirror)
        .change(null);
    service.blocked!.complete(_snapshot(outer: true, manual: true));
    await pending;
    expect(container.read(foldableScreenProvider('device')).snapshot, isNull);
    expect(service.releases, 1);
  });
}
