import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/android_emulator.dart';
import '../../emulator/emulator_service.dart';
import '../../emulator/emulator_process.dart';
import '../../terminal/adb_terminal_session.dart';
import '../../terminal/favorite_commands.dart';
import 'device_tracking_providers.dart';
import 'service_providers.dart';

/// 终端调试会话列表 Provider（按设备隔离管理终端流与输入）。
final adbTerminalProvider =
    NotifierProvider<AdbTerminalNotifier, AdbTerminalState>(
      AdbTerminalNotifier.new,
    );

/// 收藏与常用调试命令列表 Provider。
final favoriteCommandsProvider =
    NotifierProvider<FavoriteCommandsNotifier, List<FavoriteCommand>>(
      FavoriteCommandsNotifier.new,
    );

/// 模拟器底层管理服务实例 Provider。
final emulatorServiceProvider = Provider<EmulatorService>((ref) {
  return EmulatorService(
    hostPlatformService: ref.watch(hostPlatformServiceProvider),
  );
});

/// 宿主机可用 AVD Android 模拟器配置列表 Provider。
final emulatorListProvider = FutureProvider.autoDispose<List<AndroidEmulator>>((
  ref,
) async {
  return ref.watch(emulatorServiceProvider).listEmulators();
});

/// 按 AVD 保存启动结果，切换 Tab 后仍持续跟踪失败和超时。
final emulatorLaunchProvider =
    NotifierProvider<EmulatorLaunchNotifier, Map<String, EmulatorLaunchState>>(
      EmulatorLaunchNotifier.new,
    );

/// 进程创建、ADB 上线和进程退出分开处理，防止永久“启动中”。
class EmulatorLaunchNotifier
    extends Notifier<Map<String, EmulatorLaunchState>> {
  EmulatorLaunchNotifier({this.startupTimeout = const Duration(minutes: 2)});

  final Duration startupTimeout;
  final Map<String, Timer> _timers = {};
  bool _disposed = false;
  ProviderSubscription<AsyncValue<Map<String, String>>>? _runningSubscription;

  @override
  Map<String, EmulatorLaunchState> build() {
    ref.onDispose(() {
      _disposed = true;
      _runningSubscription?.close();
      for (final timer in _timers.values) {
        timer.cancel();
      }
    });
    return {};
  }

  /// 启动期间使用显式订阅，避免 Tab 卸载导致 Riverpod 暂停上线监听。
  /// 全部启动结束后关闭订阅，不为已启动的模拟器长期增加设备查询。
  void _observeRunning() {
    _runningSubscription ??= ref.container.listen(runningEmulatorsProvider, (
      _,
      next,
    ) {
      if (_disposed || next.isLoading) return;
      for (final name in (next.value ?? {}).keys) {
        final current = state[name];
        if (current == null ||
            (!current.starting &&
                current.errorKey != 'emulatorLaunchTimeout')) {
          continue;
        }
        _timers.remove(name)?.cancel();
        state = {...state, name: const EmulatorLaunchState(processAlive: true)};
      }
      _releaseRunningObserver();
    });
  }

  void _releaseRunningObserver() {
    final pending = state.values.any(
      (value) => value.starting || value.errorKey == 'emulatorLaunchTimeout',
    );
    if (pending) return;
    _runningSubscription?.close();
    _runningSubscription = null;
  }

  /// 重复点击不创建第二个进程；超时后仍存活的进程也不能重复启动。
  Future<void> launch(String name) async {
    if (state[name]?.processAlive == true || state[name]?.starting == true) {
      return;
    }
    state = {...state, name: const EmulatorLaunchState(starting: true)};
    try {
      final process = await ref
          .read(emulatorServiceProvider)
          .startEmulator(name);
      if (_disposed) return;
      state = {
        ...state,
        name: const EmulatorLaunchState(starting: true, processAlive: true),
      };
      _timers[name] = Timer(startupTimeout, () {
        _timers.remove(name);
        if (_disposed || state[name]?.starting != true) return;
        state = {
          ...state,
          name: EmulatorLaunchState(
            processAlive: true,
            errorKey: 'emulatorLaunchTimeout',
            details: process.output(),
          ),
        };
      });
      // 即便列表已卸载，也要记录后续退出结果，避免丢失启动错误。
      unawaited(_observeExit(name, process));
      _observeRunning();
      ref.invalidate(runningEmulatorsProvider);
    } catch (error) {
      if (_disposed) return;
      state = {
        ...state,
        name: EmulatorLaunchState(
          errorKey: 'emulatorLaunchFailed',
          details: error.toString(),
        ),
      };
    }
  }

  Future<void> _observeExit(String name, EmulatorProcess process) async {
    try {
      final result = await process.exited;
      if (_disposed) return;
      _timers.remove(name)?.cancel();
      final current = state[name];
      final failed =
          result.code != 0 ||
          current?.starting == true ||
          current?.errorKey != null;
      state = {
        ...state,
        name: EmulatorLaunchState(
          errorKey: failed ? 'emulatorLaunchExited' : null,
          details: failed ? result.output : '',
          exitCode: failed ? result.code : null,
        ),
      };
      _releaseRunningObserver();
      ref.invalidate(runningEmulatorsProvider);
    } catch (error) {
      if (_disposed) return;
      _timers.remove(name)?.cancel();
      state = {
        ...state,
        name: EmulatorLaunchState(
          processAlive: true,
          errorKey: 'emulatorLaunchObserveFailed',
          details: error.toString(),
        ),
      };
      _releaseRunningObserver();
    }
  }
}

/// 当前正在运行的模拟器映射 Provider（Map 格式：AVD 名称 -> 对应的 ADB 设备 ID）。
final runningEmulatorsProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      final devicesAsync = ref.watch(devicesProvider);
      final devices = devicesAsync.value ?? [];
      final adb = ref.read(adbServiceProvider);
      final map = <String, String>{};

      for (final device in devices) {
        if (device.isOnline) {
          try {
            var result = await adb.shellArgs(device.id, [
              'getprop',
              'ro.boot.qemu.avd_name',
            ]);
            var avdName = result.isSuccess ? result.stdout.trim() : '';
            if (avdName.isEmpty) {
              result = await adb.shellArgs(device.id, [
                'getprop',
                'ro.kernel.qemu.avd_name',
              ]);
              avdName = result.isSuccess ? result.stdout.trim() : '';
            }

            if (avdName.isNotEmpty) {
              map[avdName] = device.id;
            }
          } catch (_) {}
        }
      }

      return map;
    });
