import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/android_emulator.dart';
import '../../emulator/emulator_connection.dart';
import '../../adb/adb_device.dart';
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
    adbService: ref.watch(adbServiceProvider),
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
  ProviderSubscription<AsyncValue<Map<String, AdbDevice>>>?
  _runningSubscription;

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
  /// 进程退出后释放订阅；存活期间继续接收授权状态变化。
  void _observeRunning() {
    _runningSubscription ??= ref.container.listen(emulatorConnectionsProvider, (
      _,
      next,
    ) {
      if (_disposed || next.isLoading) return;
      for (final entry in (next.value ?? <String, AdbDevice>{}).entries) {
        final name = entry.key;
        final current = state[name];
        if (current == null || !current.processAlive) continue;
        _timers.remove(name)?.cancel();
        state = {
          ...state,
          name: EmulatorLaunchState(
            processAlive: true,
            errorKey: entry.value.isOnline
                ? null
                : entry.value.status == 'unauthorized'
                ? 'emulatorAdbUnauthorized'
                : 'emulatorAdbOffline',
          ),
        };
      }
      _releaseRunningObserver();
    });
  }

  void _releaseRunningObserver() {
    final pending = state.values.any(
      (value) => value.starting || value.processAlive,
    );
    if (pending) return;
    _runningSubscription?.close();
    _runningSubscription = null;
  }

  /// 重复点击不创建第二个进程；超时后仍存活的进程也不能重复启动。
  Future<void> launch(String name, {bool coldBoot = false}) async {
    if (state[name]?.processAlive == true || state[name]?.starting == true) {
      return;
    }
    state = {...state, name: const EmulatorLaunchState(starting: true)};
    try {
      final process = await ref
          .read(emulatorServiceProvider)
          .startEmulator(name, coldBoot: coldBoot);
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
      ref.invalidate(emulatorConnectionsProvider);
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
          (current?.errorKey != null && current?.isConnectionIssue != true);
      state = {
        ...state,
        name: EmulatorLaunchState(
          errorKey: failed ? 'emulatorLaunchExited' : null,
          details: failed ? result.output : '',
          exitCode: failed ? result.code : null,
        ),
      };
      _releaseRunningObserver();
      ref.invalidate(emulatorConnectionsProvider);
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

/// 包括未授权/离线的模拟器映射，避免只查 shell 而遗漏已运行的 AVD。
final emulatorConnectionsProvider =
    FutureProvider.autoDispose<Map<String, AdbDevice>>((ref) async {
      final devices = ref.watch(devicesProvider).value ?? [];
      return EmulatorConnectionService(
        ref.read(adbServiceProvider),
      ).inspect(devices);
    });

/// 兼容现有调用者：此映射仅表示可执行 ADB shell 的模拟器。
final runningEmulatorsProvider =
    FutureProvider.autoDispose<Map<String, String>>((ref) async {
      final connections = await ref.watch(emulatorConnectionsProvider.future);
      return {
        for (final entry in connections.entries)
          if (entry.value.isOnline) entry.key: entry.value.id,
      };
    });
