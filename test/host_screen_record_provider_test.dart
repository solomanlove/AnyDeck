import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/host_recording_backend.dart';
import 'package:any_deck/core/scrcpy/screen_record_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/host_recording_fakes.dart';

void main() {
  late Directory dir;
  late RecordingTestAdb adb;
  late RecordingTestHost host;
  late ProviderContainer container;
  late String destination;
  ProviderContainer create({bool force = true}) => ProviderContainer(
    overrides: [
      appSettingsProvider.overrideWith(
        () => RecordingTestSettings(dir.path, force),
      ),
      deviceRegistryProvider.overrideWith(RecordingTestRegistry.new),
      adbServiceProvider.overrideWithValue(adb),
      hostRecordingFactoryProvider.overrideWithValue((device, path) {
        destination = path;
        return host;
      }),
    ],
  );
  setUp(() {
    dir = Directory.systemTemp.createTempSync('anydeck-host-provider-');
    adb = RecordingTestAdb();
    host = RecordingTestHost();
    container = create();
  });
  tearDown(() {
    container.dispose();
    dir.deleteSync(recursive: true);
  });

  test('强制本地录制只创建一个内置会话，等待收尾后才返回本地路径', () async {
    host.starting = Completer<void>();
    final notifier = container.read(screenRecordProvider('test').notifier);
    final start = notifier.start();
    await host.entered.future;
    await notifier.start();
    expect(host.starts, 1);
    expect(container.read(screenRecordProvider('test')).isStarting, isTrue);
    host.starting!.complete();
    await start;
    expect(container.read(screenRecordProvider('test')).isRecording, isTrue);
    host.stopping = Completer<void>();
    final stopping = notifier.stop();
    expect(container.read(screenRecordProvider('test')).isStopping, isTrue);
    host.stopping!.complete();
    expect(await stopping, 'local:$destination');
    expect(container.read(screenRecordProvider('test')).isRecording, isFalse);
  });

  test('设备无 screenrecord 时自动使用内置录制', () async {
    container.dispose();
    adb.supported = false;
    container = create(force: false);
    final notifier = container.read(screenRecordProvider('test').notifier);
    await notifier.start();
    expect(host.starts, 1);
    await notifier.stop();
  });

  test('原生收尾失败不能返回成功路径', () async {
    host.failStop = true;
    final notifier = container.read(screenRecordProvider('test').notifier);
    await notifier.start();
    await expectLater(notifier.stop(), throwsStateError);
    expect(container.read(screenRecordProvider('test')).isRecording, isFalse);
  });

  test('后台断线回到 idle 并保留错误供 UI 提示', () async {
    final notifier = container.read(screenRecordProvider('test').notifier);
    await notifier.start();
    host.exit.complete('device disconnected');
    await Future<void>.delayed(Duration.zero);
    final state = container.read(screenRecordProvider('test'));
    expect(state.isRecording, isFalse);
    expect(state.error, 'device disconnected');
    expect(host.stops, 1);
  });

  test('启动期间销毁 Provider 会取消内置会话，迟到完成不会恢复录制', () async {
    host.starting = Completer<void>();
    final starting = container
        .read(screenRecordProvider('test').notifier)
        .start();
    await host.entered.future;
    container.dispose();
    expect(host.cancellations, 1);
    host.starting!.complete();
    await starting;
    expect(host.stops, greaterThanOrEqualTo(1));
    container = create();
    expect(container.read(screenRecordProvider('test')).isRecording, isFalse);
  });

  test('虚拟副屏保持设备端录制，不误录手机主屏', () async {
    final notifier = container.read(screenRecordProvider('test').notifier);
    await expectLater(notifier.start(displayId: 42), throwsStateError);
    expect(host.starts, 0);
    expect(adb.displayCalls, 1);
  });
}
