import 'dart:async';
import 'dart:io';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/device_discovery_tracker.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowIosDevices extends IosDeviceService {
  final pending = Completer<List<DiscoveredDevice>>();
  int calls = 0;

  @override
  Future<List<DiscoveredDevice>> listDevices() {
    calls++;
    return pending.future;
  }
}

/// 隔离真实 CLI，模拟 ADB 不可用时 HDC 仍能独立检测。
class _UnavailableAdb extends AdbService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => throw StateError('ADB');

  @override
  Future<Process> start(List<String> args) async => throw StateError('ADB');
}

/// 可控制结果和完成时机的 HDC，用于验证热插拔、重入和退出边界。
class _HarmonyDevices extends HdcService {
  int calls = 0;
  List<DiscoveredDevice> devices = [];
  Completer<List<DiscoveredDevice>>? pending;
  bool fail = false;

  @override
  Future<List<DiscoveredDevice>> listDevices() async {
    calls++;
    if (fail) throw StateError('HDC');
    return pending == null ? devices : await pending!.future;
  }
}

const _harmonyDevice = DiscoveredDevice(
  id: 'harmony-usb',
  status: 'device',
  model: 'HarmonyOS Device',
  product: 'HarmonyOS NEXT',
  transportId: '',
  isHarmony: true,
);

void main() {
  test('HDC 自动发现插拔，仅变化时发布，ADB 失败不阻塞，退出停止检测', () {
    fakeAsync((clock) {
      final hdc = _HarmonyDevices();
      final tracker = DeviceDiscoveryTracker(
        adbService: _UnavailableAdb(),
        hdcService: hdc,
      );
      final events = <List<DiscoveredDevice>>[];
      tracker.deviceStream.listen(events.add);
      clock.flushMicrotasks();
      expect(hdc.calls, 1);

      hdc.devices = [_harmonyDevice];
      clock.elapse(const Duration(seconds: 2));
      expect(tracker.currentDevices.single.id, 'harmony-usb');
      expect(events, hasLength(1));
      clock.elapse(const Duration(seconds: 2));
      expect(events, hasLength(1));

      hdc.devices = [];
      clock.elapse(const Duration(seconds: 2));
      expect(tracker.currentDevices, isEmpty);
      expect(events, hasLength(2));

      tracker.dispose();
      final calls = hdc.calls;
      clock.elapse(const Duration(seconds: 10));
      expect(hdc.calls, calls);
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('HDC 慢请求与手动刷新合并，退出忽略迟到结果', () {
    fakeAsync((clock) {
      final hdc = _HarmonyDevices()..pending = Completer();
      final tracker = DeviceDiscoveryTracker(
        adbService: _UnavailableAdb(),
        hdcService: hdc,
      );
      clock.flushMicrotasks();
      var completed = false;
      tracker.refreshHarmonyDevices().then((_) => completed = true);
      clock.elapse(const Duration(seconds: 6));
      expect(hdc.calls, 1);
      expect(completed, isFalse);
      tracker.dispose();
      hdc.pending!.complete([_harmonyDevice]);
      clock.flushMicrotasks();
      expect(completed, isTrue);
      expect(tracker.currentDevices, isEmpty);
      tracker.refreshHarmonyDevices();
      clock.flushMicrotasks();
      expect(hdc.calls, 1);
    });
  });

  test('HDC 检测失败保留快照，后续自动恢复', () {
    fakeAsync((clock) {
      final hdc = _HarmonyDevices()..devices = [_harmonyDevice];
      final tracker = DeviceDiscoveryTracker(
        adbService: _UnavailableAdb(),
        hdcService: hdc,
      );
      clock.flushMicrotasks();
      hdc.fail = true;
      clock.elapse(const Duration(seconds: 2));
      expect(tracker.currentDevices, hasLength(1));
      hdc.fail = false;
      hdc.devices = [];
      clock.elapse(const Duration(seconds: 2));
      expect(tracker.currentDevices, isEmpty);
      tracker.dispose();
    });
  });

  test('子窗口不启动 HDC 自动检测', () {
    fakeAsync((clock) {
      final hdc = _HarmonyDevices();
      final tracker = DeviceDiscoveryTracker(
        adbService: _UnavailableAdb(),
        hdcService: hdc,
        isSubWindow: true,
      );
      clock.elapse(const Duration(seconds: 10));
      expect(hdc.calls, 0);
      tracker.dispose();
    });
  });

  test('iOS 设备发现慢请求不会重入', () async {
    final ios = _SlowIosDevices();
    final tracker = DeviceDiscoveryTracker(
      adbService: AdbService(executable: 'adb'),
      iosDeviceService: ios,
      isSubWindow: true,
    );
    addTearDown(tracker.dispose);

    final first = tracker.refreshIosDevices();
    final second = tracker.refreshIosDevices();
    expect(ios.calls, 1);
    ios.pending.complete(const []);
    await Future.wait([first, second]);
  });
}
