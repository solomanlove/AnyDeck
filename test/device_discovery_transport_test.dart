import 'dart:convert';
import 'dart:io';

import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/adb/device_discovery_tracker.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_process.dart';

const _phone = DiscoveredDevice(
  id: 'fixture-phone',
  status: 'device',
  model: 'Fixture_Phone',
  product: 'fixture_product',
  transportId: '72',
);

/// 通过真实 track-devices 帧格式推进发现器，不启动外部 ADB Server。
class _TrackingAdb extends AdbService {
  final process = ControlledProcess();

  @override
  Future<List<DiscoveredDevice>> listDevices() async => [_phone];

  @override
  Future<Process> start(List<String> args) async {
    expect(args, ['track-devices', '-l']);
    return process;
  }

  void publish(String transportId) {
    final payload = utf8.encode(
      '${_phone.id}\tdevice product:${_phone.product} '
      'model:${_phone.model} transport_id:$transportId\n',
    );
    process.output.add([
      ...ascii.encode(payload.length.toRadixString(16).padLeft(4, '0')),
      ...payload,
    ]);
  }
}

void main() {
  test('在线设备仅 transport 改变时发布新快照并更新共享可读取的绑定', () {
    fakeAsync((clock) {
      final adb = _TrackingAdb();
      final tracker = DeviceDiscoveryTracker(adbService: adb);
      final updates = <List<DiscoveredDevice>>[];
      tracker.deviceStream.listen(updates.add);
      try {
        clock.flushMicrotasks();
        expect(updates, hasLength(1));
        expect(tracker.currentDevices.single.transportId, '72');

        adb.publish('99');
        clock.flushMicrotasks();

        expect(updates, hasLength(2));
        expect(updates.last.single.id, _phone.id);
        expect(updates.last.single.status, _phone.status);
        expect(updates.last.single.model, _phone.model);
        expect(updates.last.single.product, _phone.product);
        expect(updates.last.single.transportId, '99');
        expect(tracker.currentDevices, same(updates.last));
        expect(tracker.currentDevices.single.transportId, '99');
      } finally {
        tracker.dispose();
        clock.flushMicrotasks();
      }
    });
  });

  test('设备和 transport 均未改变时不重复发布 track-devices 快照', () {
    fakeAsync((clock) {
      final adb = _TrackingAdb();
      final tracker = DeviceDiscoveryTracker(adbService: adb);
      final updates = <List<DiscoveredDevice>>[];
      tracker.deviceStream.listen(updates.add);
      try {
        clock.flushMicrotasks();
        final initial = tracker.currentDevices;

        adb.publish('72');
        adb.publish('72');
        clock.flushMicrotasks();

        expect(updates, hasLength(1));
        expect(tracker.currentDevices, same(initial));
      } finally {
        tracker.dispose();
        clock.flushMicrotasks();
      }
    });
  });
}
