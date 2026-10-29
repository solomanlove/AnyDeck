import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/mirror_transport_devices_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 adb track-devices 管道和迟到进程，验证子窗口无轮询且只持有一个监听。
class _TrackProcess extends Fake implements Process {
  final output = StreamController<List<int>>();
  bool killed = false;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    unawaited(output.close());
    return true;
  }

  void publish(String payload) {
    final bytes = utf8.encode(payload);
    output.add([
      ...utf8.encode(bytes.length.toRadixString(16).padLeft(4, '0')),
      ...bytes,
    ]);
  }
}

class _TrackerAdb extends AdbService {
  final process = _TrackProcess();
  final calls = <List<String>>[];
  Completer<Process>? launch;
  @override
  Future<List<AdbDevice>> listDevices() async {
    calls.add(['devices', '-l']);
    return const [AdbDevice(id: '192.168.1.8:5555', status: 'device')];
  }

  @override
  Future<Process> start(List<String> args) async {
    calls.add(args);
    return launch == null ? process : await launch!.future;
  }
}

void main() {
  test('子窗口多个订阅共享一条 track-devices，设备事件推送且释放时终止', () async {
    final adb = _TrackerAdb();
    final container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('mirror-test'),
        adbServiceProvider.overrideWithValue(adb),
      ],
    );
    final updates = <List<AdbDevice>>[];
    container.listen(mirrorTransportDevicesProvider, (_, next) {
      if (next.hasValue) updates.add(next.requireValue);
    });
    container.listen(mirrorTransportDevicesProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(adb.calls, [
      ['devices', '-l'],
      ['track-devices', '-l'],
    ]);
    adb.process.publish('phone\tdevice\n192.168.1.8:5555\tdevice\n');
    await Future<void>.delayed(Duration.zero);
    expect(updates.last.map((d) => d.id), ['phone', '192.168.1.8:5555']);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(adb.process.killed, isTrue);
  });

  test('关窗后 track-devices 启动才返回也会终止，不残留监听进程', () async {
    final adb = _TrackerAdb()..launch = Completer<Process>();
    final container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('mirror-test'),
        adbServiceProvider.overrideWithValue(adb),
      ],
    );
    container.listen(mirrorTransportDevicesProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    adb.launch!.complete(adb.process);
    await Future<void>.delayed(Duration.zero);
    expect(adb.process.killed, isTrue);
  });
}
