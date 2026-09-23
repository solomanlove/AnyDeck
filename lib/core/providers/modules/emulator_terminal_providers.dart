import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/android_emulator.dart';
import '../../emulator/emulator_service.dart';
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

/// 正在冷启动中的模拟器名称集合状态控制器。
class StartingEmulatorsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  /// 标记某模拟器进入启动中状态
  void start(String name) {
    state = {...state, name};
  }

  /// 停止或完成启动状态
  void stopStarting(String name) {
    state = state.where((n) => n != name).toSet();
  }

  /// 批量更新启动状态集合
  void setStarting(Set<String> next) {
    state = next;
  }
}

/// 处于启动中状态的模拟器集合 Provider。
final startingEmulatorsProvider =
    NotifierProvider<StartingEmulatorsNotifier, Set<String>>(
      StartingEmulatorsNotifier.new,
    );

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

      // 如果某些处于 starting 状态的模拟器已经在 running 映射中出现，将它们从 starting 状态移除。
      final startingNotifier = ref.read(startingEmulatorsProvider.notifier);
      final starting = ref.read(startingEmulatorsProvider);
      if (starting.isNotEmpty) {
        final nextStarting = Set<String>.from(starting);
        bool changed = false;
        for (final runningAvd in map.keys) {
          if (nextStarting.contains(runningAvd)) {
            nextStarting.remove(runningAvd);
            changed = true;
          }
        }
        if (changed) {
          Future.microtask(() {
            startingNotifier.setStarting(nextStarting);
          });
        }
      }

      return map;
    });
