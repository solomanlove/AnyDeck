import 'dart:async';

import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/auxiliary_backend.dart';
import 'package:any_deck/core/scrcpy/device_capture_compatibility.dart';
import 'package:any_deck/features/control/controller/audio_forward_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记录音频转发唤醒命令，避免测试访问真实 ADB 设备。
class _FakeAdbService extends AdbService {
  _FakeAdbService() : super(executable: 'adb');

  List<String>? lastShellArgs;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    lastShellArgs = args;
    return const AdbResult(exitCode: 0, stdout: '', stderr: '');
  }
}

/// 提供可控停止时机的纯音频后台 Session。
class _FakeAudioBackend implements AuxiliaryBackend {
  int starts = 0;
  int stops = 0;
  bool cancelled = false;
  Completer<void>? pendingStop;
  final exit = Completer<void>();

  @override
  Stream<String> get clipboard => const Stream.empty();

  @override
  Future<void> get exited => exit.future;

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
    await pendingStop?.future;
  }

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<void> mute(bool muted) async {}

  @override
  Future<void> refresh() async {}
}

void main() {
  test('纯音频转发使用独立后台 Session 并展示启停状态', () async {
    final adb = _FakeAdbService();
    final backend = _FakeAudioBackend()..pendingStop = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(adb),
        captureSdkProvider('phone').overrideWith((ref) async => 31),
        deviceOnlineProvider('phone').overrideWith((ref) => true),
        audioPlaybackBackendFactoryProvider.overrideWithValue((_) => backend),
      ],
    );
    addTearDown(container.dispose);
    container.listen(audioForwardControllerProvider('phone'), (_, _) {});
    final controller = container.read(
      audioForwardControllerProvider('phone').notifier,
    );

    expect(await controller.start(), true);
    expect(backend.starts, 1);
    expect(adb.lastShellArgs, ['input', 'keyevent', '224']);
    expect(
      container.read(audioForwardControllerProvider('phone')).isActive,
      true,
    );

    final stop = controller.stop();
    await Future<void>.delayed(Duration.zero);
    final stopping = container.read(audioForwardControllerProvider('phone'));
    expect(stopping.isActive, true);
    expect(stopping.isStopping, true);

    backend.pendingStop!.complete();
    await stop;
    expect(backend.stops, 1);
    expect(
      container.read(audioForwardControllerProvider('phone')).isActive,
      false,
    );
  });

  test('Android 10 不创建纯音频后台 Session', () async {
    final backend = _FakeAudioBackend();
    final container = ProviderContainer(
      overrides: [
        adbServiceProvider.overrideWithValue(_FakeAdbService()),
        captureSdkProvider('phone').overrideWith((ref) async => 29),
        deviceOnlineProvider('phone').overrideWith((ref) => true),
        audioPlaybackBackendFactoryProvider.overrideWithValue((_) => backend),
      ],
    );
    addTearDown(container.dispose);
    container.listen(audioForwardControllerProvider('phone'), (_, _) {});

    final started = await container
        .read(audioForwardControllerProvider('phone').notifier)
        .start();

    expect(started, false);
    expect(backend.starts, 0);
    expect(
      container.read(audioForwardControllerProvider('phone')).errorMessage,
      'unsupported',
    );
  });
}
