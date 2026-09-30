import 'dart:async';
import 'package:any_deck/core/adb/adb_device.dart';

import 'package:any_deck/core/emulator/emulator_process.dart';
import 'package:any_deck/core/emulator/emulator_service.dart';
import 'package:any_deck/core/providers/modules/emulator_terminal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通过可控进程退出和 ADB 映射验证生命周期，不调用真实设备命令。
class _FakeEmulatorService extends EmulatorService {
  final exits = <Completer<EmulatorExit>>[];
  bool throwOnStart = false;

  @override
  Future<EmulatorProcess> startEmulator(
    String avdName, {
    bool coldBoot = false,
  }) async {
    if (throwOnStart) throw StateError('emulator executable missing');
    final exit = Completer<EmulatorExit>();
    exits.add(exit);
    return EmulatorProcess(
      exited: exit.future,
      output: () => 'waiting for ADB',
    );
  }
}

void main() {
  late ProviderContainer container;
  late _FakeEmulatorService service;
  late Map<String, AdbDevice> running;

  setUp(() {
    service = _FakeEmulatorService();
    running = {};
    container = ProviderContainer(
      overrides: [
        emulatorServiceProvider.overrideWithValue(service),
        emulatorConnectionsProvider.overrideWith((ref) async => running),
        emulatorLaunchProvider.overrideWith(
          () => EmulatorLaunchNotifier(
            startupTimeout: const Duration(milliseconds: 20),
          ),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  test(
    'early failure clears starting, retains error and allows retry',
    () async {
      final notifier = container.read(emulatorLaunchProvider.notifier);
      await notifier.launch('phone');
      expect(container.read(emulatorLaunchProvider)['phone']!.starting, isTrue);
      service.exits.first.complete(
        const EmulatorExit(1, 'Missing system image'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final state = container.read(emulatorLaunchProvider)['phone']!;
      expect(state.starting, isFalse);
      expect(state.processAlive, isFalse);
      expect(state.exitCode, 1);
      expect(state.details, 'Missing system image');
      await notifier.launch('phone');
      expect(service.exits, hasLength(2));
      expect(container.read(emulatorLaunchProvider)['phone']!.errorKey, isNull);
    },
  );

  test('zero exit before ADB online is not a successful launch', () async {
    await container.read(emulatorLaunchProvider.notifier).launch('phone');
    service.exits.first.complete(const EmulatorExit(0, 'cannot boot'));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(
      container.read(emulatorLaunchProvider)['phone']!.errorKey,
      'emulatorLaunchExited',
    );
  });

  test('timeout becomes visible and prevents duplicate live process', () async {
    final notifier = container.read(emulatorLaunchProvider.notifier);
    await notifier.launch('phone');
    await notifier.launch('phone');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final state = container.read(emulatorLaunchProvider)['phone']!;
    expect(state.starting, isFalse);
    expect(state.errorKey, 'emulatorLaunchTimeout');
    expect(state.processAlive, isTrue);
    await notifier.launch('phone');
    expect(service.exits, hasLength(1));
    running = {'phone': const AdbDevice(id: 'emulator-5554', status: 'device')};
    container.invalidate(emulatorConnectionsProvider);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(container.read(emulatorLaunchProvider)['phone']!.errorKey, isNull);
    service.exits.first.complete(const EmulatorExit(0, ''));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    expect(
      container.read(emulatorLaunchProvider)['phone']!.processAlive,
      isFalse,
    );
    expect(container.read(emulatorLaunchProvider)['phone']!.errorKey, isNull);
  });

  test(
    'unauthorized is a connection issue and clears when authorized',
    () async {
      await container.read(emulatorLaunchProvider.notifier).launch('phone');
      running = {
        'phone': const AdbDevice(id: 'emulator-5554', status: 'unauthorized'),
      };
      container.invalidate(emulatorConnectionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final waiting = container.read(emulatorLaunchProvider)['phone']!;
      expect(waiting.starting, isFalse);
      expect(waiting.isConnectionIssue, isTrue);
      expect(waiting.errorKey, 'emulatorAdbUnauthorized');
      running = {
        'phone': const AdbDevice(id: 'emulator-5554', status: 'device'),
      };
      container.invalidate(emulatorConnectionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(container.read(emulatorLaunchProvider)['phone']!.errorKey, isNull);
      service.exits.first.complete(const EmulatorExit(0, ''));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(container.read(emulatorLaunchProvider)['phone']!.errorKey, isNull);
    },
  );

  test('spawn exception clears busy state', () async {
    service.throwOnStart = true;
    await container.read(emulatorLaunchProvider.notifier).launch('phone');
    final state = container.read(emulatorLaunchProvider)['phone']!;
    expect(state.starting, isFalse);
    expect(state.errorKey, 'emulatorLaunchFailed');
    expect(state.details, contains('executable missing'));
  });

  test(
    'late exit after provider disposal does not update disposed state',
    () async {
      await container.read(emulatorLaunchProvider.notifier).launch('phone');
      container.dispose();
      service.exits.first.complete(const EmulatorExit(1, 'late failure'));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      // 若销毁后仍写入 Provider，测试会收到未处理异常。
    },
  );
}
