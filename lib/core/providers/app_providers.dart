import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/settings/app_settings_controller.dart';

import '../../common/utils/network_util.dart';
import '../adb/adb_device.dart';
import '../adb/adb_device_tracker.dart';
import '../adb/adb_heartbeat_controller.dart';
import '../adb/adb_result.dart';
import '../adb/adb_service.dart';
import '../apps/app_data_backup_service.dart';
import '../apps/adb_package.dart';
import '../apps/app_management_service.dart';
import '../apps/package_refresh_progress.dart';
import '../apps/package_refresh_runner.dart';
import '../apps/app_permission_service.dart';
import '../cache/cache_cleanup_service.dart';
import '../device_actions/device_action_service.dart';
import '../device_actions/foreground_app_service.dart';
import '../device_info/device_info_service.dart';
import '../device_info/device_memory_info.dart';
import '../device_info/device_overview.dart';
import '../emulator/android_emulator.dart';
import '../files/file_manager_service.dart';
import '../layout_inspector/layout_inspector_service.dart';
import '../files/remote_file.dart';
import '../logcat/logcat_controller.dart';
import '../logcat/logcat_state.dart';
import '../scrcpy/scrcpy_service.dart';
import '../scrcpy/scrcpy_session.dart';
import '../scrcpy/embedded_scrcpy_service.dart';
import '../terminal/adb_terminal_session.dart';
import '../terminal/favorite_commands.dart';
import '../emulator/emulator_service.dart';
import '../process/host_platform_service.dart';
import '../process/process_service.dart';
import '../web_debug/webpage_target.dart';
import '../web_debug/web_debug_service.dart';

import '../logging/log_service.dart';
import '../ios/ios_mirror_service.dart';
import '../harmony/hdc_service.dart';
import '../harmony/harmony_mirror_service.dart';

export '../ios/ios_ble_mouse_service.dart';
export '../ios/ios_wda_client.dart';
export '../cron/cron_scheduler_service.dart';

/// 所有命令型 provider 共享的 adb 服务实例。
final adbServiceProvider = Provider<AdbService>((ref) {
  return AdbService(
    onLog: (message, {tag = 'adb', level = 'I'}) {
      ref
          .read(logHistoryProvider.notifier)
          .log(message, tag: tag, level: level);
    },
  );
});

/// 所有命令型 provider 共享的 hdc 服务实例。
final hdcServiceProvider = Provider<HdcService>((ref) {
  return HdcService(
    onLog: (message, {tag = 'hdc', level = 'I'}) {
      ref
          .read(logHistoryProvider.notifier)
          .log(message, tag: tag, level: level);
    },
  );
});

/// 鸿蒙镜像（投屏）管理服务实例。
final harmonyMirrorServiceProvider = Provider<HarmonyMirrorService>((ref) {
  final hdcService = ref.watch(hdcServiceProvider);
  final service = HarmonyMirrorService(hdcService);
  ref.onDispose(service.stopAll);
  return service;
});

/// 设备操作门面，负责 key event、开关和 shell 读取。
final deviceActionServiceProvider = Provider<DeviceActionService>((ref) {
  return DeviceActionService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
    sdkVersionResolver: (deviceId) =>
        ref.read(deviceSdkVersionProvider(deviceId)),
    isHarmonyResolver: (deviceId) {
      if (deviceId.startsWith('harmony:')) return true;
      if (ref.read(harmonyMirrorServiceProvider).isActive(deviceId)) return true;
      final registered = ref.read(deviceRegistryProvider);
      return registered.any((d) => d.id == deviceId && d.isHarmony);
    },
  );
});

/// 前台应用识别门面，负责投屏窗口长按返回键的应用判断与强停。
final foregroundAppServiceProvider = Provider<ForegroundAppService>((ref) {
  return ForegroundAppService(ref.watch(adbServiceProvider));
});

/// 应用管理门面，负责安装、卸载、启动和列表读取。
final appManagementServiceProvider = Provider<AppManagementService>((ref) {
  return AppManagementService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
  );
});

/// 应用数据备份门面，负责按系统版本选择 adb backup、run-as 或 Root tar。
final appDataBackupServiceProvider = Provider<AppDataBackupService>((ref) {
  return AppDataBackupService(ref.watch(adbServiceProvider));
});

/// 应用权限管理门面，负责查询、授予和撤销应用权限。
final appPermissionServiceProvider = Provider<AppPermissionService>((ref) {
  return AppPermissionService(ref.watch(adbServiceProvider));
});

/// 远程文件管理门面，负责 adb/hdc push/pull 和目录列表。
final fileManagerServiceProvider = Provider<FileManagerService>((ref) {
  return FileManagerService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
    isHarmonyResolver: (deviceId) {
      final registered = ref.read(deviceRegistryProvider);
      return registered.any((d) => d.id == deviceId && d.isHarmony);
    },
  );
});

/// 只读设备概览服务。
final deviceInfoServiceProvider = Provider<DeviceInfoService>((ref) {
  return DeviceInfoService(ref.watch(adbServiceProvider));
});

/// 布局分析服务，负责抓取 `uiautomator` XML 和屏幕截图。
final layoutInspectorServiceProvider = Provider<LayoutInspectorService>((ref) {
  return LayoutInspectorService(ref.watch(adbServiceProvider));
});

/// scrcpy 进程管理器，provider 销毁时会停止所有会话。
final scrcpyServiceProvider = Provider<ScrcpyService>((ref) {
  final service = ScrcpyService();
  ref.onDispose(service.stopAll);
  return service;
});

/// 进程管理门面，负责查询和结束进程。
final processServiceProvider = Provider<ProcessService>((ref) {
  return ProcessService(ref.watch(adbServiceProvider), ref.watch(hdcServiceProvider));
});

/// 宿主机系统平台服务，负责处理与宿主机 OS 交互的操作。
final hostPlatformServiceProvider = Provider<HostPlatformService>((ref) {
  return HostPlatformService();
});

/// 本机缓存清理服务，只处理 AnyDeck 自有缓存目录。
final cacheCleanupServiceProvider = Provider<CacheCleanupService>((ref) {
  return CacheCleanupService();
});

/// 单台设备的当前运行进程列表。
final processesProvider = FutureProvider.autoDispose
    .family<List<AdbProcess>, String>((ref, deviceId) {
      final registry = ref.watch(deviceRegistryProvider);
      final isHarmony = registry.any((d) => d.id == deviceId && d.isHarmony);
      return ref
          .watch(processServiceProvider)
          .getProcesses(deviceId, isHarmony: isHarmony);
    });

/// 网页调试服务。
final webDebugServiceProvider = Provider<WebDebugService>((ref) {
  final service = WebDebugService(
    ref.watch(adbServiceProvider),
    hdc: ref.watch(hdcServiceProvider),
  );
  ref.onDispose(service.disposeAll);
  return service;
});

/// 单台设备的运行网页调试目标列表。
final webTargetsProvider = FutureProvider.autoDispose
    .family<List<WebpageTarget>, String>((ref, deviceId) async {
      final service = ref.watch(webDebugServiceProvider);
      final showAllTargets = ref.watch(showAllWebTargetsProvider);
      final isHarmony = ref
          .read(deviceRegistryProvider)
          .any((d) => d.id == deviceId && d.isHarmony);
      await Future<void>.delayed(Duration.zero);
      return service.scanTargets(
        deviceId,
        includeAllTargets: showAllTargets,
        isHarmony: isHarmony,
      );
    });

/// 选中的网页目标。
final selectedWebTargetProvider =
    NotifierProvider<SelectedWebTargetNotifier, WebpageTarget?>(
      SelectedWebTargetNotifier.new,
    );

class SelectedWebTargetNotifier extends Notifier<WebpageTarget?> {
  @override
  WebpageTarget? build() => null;

  @override
  set state(WebpageTarget? value) => super.state = value;
}

/// 是否显示 Stetho、app 等全部 DevTools 调试目标。
final showAllWebTargetsProvider =
    NotifierProvider<ShowAllWebTargetsNotifier, bool>(
      ShowAllWebTargetsNotifier.new,
    );

class ShowAllWebTargetsNotifier extends Notifier<bool> {
  static const _key = 'web_debug.show_all_targets';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    final next = !state;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
  }
}

/// 自适应心跳控制器 Provider。
final adbHeartbeatControllerProvider =
    Provider.autoDispose<AdbHeartbeatController>((ref) {
      final adbService = ref.watch(adbServiceProvider);
      final iosDeviceService = ref.watch(iosDeviceServiceProvider);
      final hdcService = ref.watch(hdcServiceProvider);
      final isSub = ref.watch(windowIdProvider).isNotEmpty;

      // 主窗口下，当没有选择设备或正处于设备管理Tab(-1)，且未展示设置页面时（即处于设备管理列表“主页”），才应该运行心跳
      final selectedDevice = ref.watch(selectedDeviceProvider);
      final selectedTool = ref.watch(selectedToolTabProvider);
      final isDeviceListVisible =
          !isSub && (selectedDevice == null || selectedTool == -1) && selectedTool != 12;

      final controller = AdbHeartbeatController(
        adbService: adbService,
        iosDeviceService: iosDeviceService,
        hdcService: hdcService,
        isSubWindow: isSub,
        isDeviceListVisible: isDeviceListVisible,
      );
      ref.onDispose(() => controller.dispose());
      return controller;
    });

/// 主窗口常驻 ADB 设备监听进程 Provider（单一长驻进程管理，退出应用时释放）。
final adbDeviceTrackerProvider = Provider<AdbDeviceTracker>((ref) {
  final adbService = ref.watch(adbServiceProvider);
  final iosService = ref.watch(iosDeviceServiceProvider);
  final hdcService = ref.watch(hdcServiceProvider);
  final isSub = ref.watch(windowIdProvider).isNotEmpty;

  final tracker = AdbDeviceTracker(
    adbService: adbService,
    iosDeviceService: iosService,
    hdcService: hdcService,
    isSubWindow: isSub,
  );

  ref.onDispose(tracker.dispose);
  return tracker;
});

/// 自动轮询/监听的实时 adb 设备列表（主窗口接入长驻 track-devices，子窗口安全回退）。
final devicesProvider = StreamProvider.autoDispose<List<AdbDevice>>((ref) {
  final isSub = ref.watch(windowIdProvider).isNotEmpty;
  if (isSub) {
    final controller = ref.watch(adbHeartbeatControllerProvider);
    return controller.deviceStream;
  }
  final tracker = ref.watch(adbDeviceTrackerProvider);
  return tracker.deviceStream;
});

/// 单台设备的已安装应用列表。
final packagesProvider = NotifierProvider.autoDispose
    .family<PackagesNotifier, AsyncValue<List<AdbPackage>>, String>(
      PackagesNotifier.new,
    );

class PackagesNotifier extends Notifier<AsyncValue<List<AdbPackage>>> {
  final String deviceId;
  PackagesNotifier(this.deviceId);

  Future<void>? _refreshAllTask;
  int _loadRevision = 0;

  RegisteredDevice? _resolveRegisteredDevice() {
    try {
      final registry = ref.read(deviceRegistryProvider);
      for (final d in registry) {
        if (d.id == deviceId ||
            d.serial == deviceId ||
            d.connections.contains(deviceId)) {
          return d;
        }
      }
    } catch (_) {}
    return null;
  }

  String? get _canonicalId {
    final dev = _resolveRegisteredDevice();
    if (dev != null && dev.serial != null && dev.serial!.isNotEmpty) {
      return dev.serial;
    }
    return null;
  }

  List<String> get _fallbackKeys {
    final dev = _resolveRegisteredDevice();
    if (dev == null) return const [];
    final keys = <String>{
      dev.id,
      if (dev.serial != null && dev.serial!.isNotEmpty) dev.serial!,
      ...dev.connections,
    }..remove(deviceId);
    return keys.toList(growable: false);
  }

  bool get _isHarmony {
    final dev = _resolveRegisteredDevice();
    return dev?.isHarmony ?? false;
  }

  @override
  AsyncValue<List<AdbPackage>> build() {
    ref.keepAlive();
    final service = ref.read(appManagementServiceProvider);
    final inMemory = service.getCachedPackagesSync(
      deviceId,
      canonicalId: _canonicalId,
      fallbackKeys: _fallbackKeys,
    );
    if (inMemory != null && inMemory.isNotEmpty) {
      _load(hasInitialData: true);
      return AsyncValue.data(inMemory);
    }
    _load();
    return const AsyncValue.loading();
  }

  Future<void> _load({bool hasInitialData = false}) async {
    final revision = _loadRevision;
    var isDisposed = false;
    ref.onDispose(() => isDisposed = true);

    try {
      final service = ref.read(appManagementServiceProvider);

      // 1. 优先尝试从本地持久化缓存加载以实现秒开（包含跨通道 fallback 回退）
      final cached = await service.loadPackageCache(
        deviceId,
        canonicalId: _canonicalId,
        fallbackKeys: _fallbackKeys,
      );
      if (cached != null && cached.isNotEmpty) {
        if (isDisposed || revision != _loadRevision) return;
        state = AsyncValue.data(cached);
        return;
      }

      // 如果已有初始内存数据（由同一设备上一通道继承），且本地无新数据，保留现状不打断用户
      if (hasInitialData && state.hasValue) {
        return;
      }

      // 2. 校验当前通道在线与就绪状态，规避 USB 刚插入时的 unauthorized / offline 瞬态
      final isOnline = ref.read(deviceOnlineProvider(deviceId));
      if (!isOnline) {
        return;
      }

      // 3. 无缓存时，只读取基础列表，避免切到 Apps Tab 就批量刷新图标。
      final initialPackages = await service.listPackages(
        deviceId,
        canonicalId: _canonicalId,
        fallbackKeys: _fallbackKeys,
        isHarmony: _isHarmony,
      );
      if (isDisposed || revision != _loadRevision) return;
      state = AsyncValue.data(initialPackages);
    } catch (err, stack) {
      // 若当前已有数据，网络或瞬态异常时不冲掉已有数据
      if (!isDisposed && revision == _loadRevision && !state.hasValue) {
        state = AsyncValue.error(err, stack);
      }
    }
  }

  /// 手动刷新全部应用时，重新读取元数据并分批加载所有应用图标。
  Future<void> refreshAllPackagesWithIcons({
    PackageRefreshCallback? onProgress,
  }) {
    final running = _refreshAllTask;
    if (running != null) return running;
    // 防止首次缓存读取晚于手动刷新完成而覆盖新列表。
    _loadRevision++;
    final runner = PackageRefreshRunner(
      service: ref.read(appManagementServiceProvider),
      deviceId: deviceId,
      canonicalId: _canonicalId,
      fallbackKeys: _fallbackKeys,
      isActive: () => ref.mounted,
      publishPackages: (packages) => state = AsyncValue.data(packages),
      isHarmony: _isHarmony,
    );
    return _refreshAllTask = runner.run(onProgress: onProgress).whenComplete(() {
      _refreshAllTask = null;
    });
  }

  /// 刷新单个应用的最新状态，并更新 state 与本地缓存。
  Future<void> refreshSinglePackage(String packageName) async {
    final current = state.value;
    if (current == null) return;

    final service = ref.read(appManagementServiceProvider);
    final updated = await service.getSinglePackageInfo(
      deviceId,
      packageName,
      isHarmony: _isHarmony,
    );

    final List<AdbPackage> newList;
    if (updated == null) {
      // 如果应用已被卸载或无法获取信息，从列表中移除它
      newList = current.where((p) => p.name != packageName).toList();
    } else {
      // 否则，在列表中替换为最新信息。鸿蒙单包刷新只返回 name/system，需保留旧
      // label/icon 等展示字段，避免点击应用后图标和名称丢失。
      final index = current.indexWhere((p) => p.name == packageName);
      if (index != -1) {
        final old = current[index];
        final merged = updated.copyWith(
          label: updated.label ?? old.label,
          iconLocalPath: updated.iconLocalPath ?? old.iconLocalPath,
          iconRemotePath: updated.iconRemotePath ?? old.iconRemotePath,
        );
        newList = List<AdbPackage>.from(current)..[index] = merged;
      } else {
        newList = List<AdbPackage>.from(current)..add(updated);
      }
    }

    state = AsyncValue.data(newList);
    await service.savePackageCache(
      deviceId,
      newList,
      canonicalId: _canonicalId,
      fallbackKeys: _fallbackKeys,
    );
  }
}

/// 用于响应式监听设备是否在线的 Provider。
final deviceOnlineProvider = Provider.autoDispose.family<bool, String>((
  ref,
  deviceId,
) {
  final isSub = ref.watch(windowIdProvider).isNotEmpty;
  if (isSub) {
    // 子 Isolate 下心跳轮询被禁用，通过是否包含激活的投屏 Session 来判断在线状态
    return ref.watch(activeIosMirrorProvider(deviceId)) != null ||
        ref.watch(activeHarmonyMirrorProvider(deviceId)) != null ||
        ref.watch(activeEmbeddedMirrorProvider(deviceId)) != null;
  }
  final activeDevicesAsync = ref.watch(devicesProvider);
  final activeDevices = activeDevicesAsync.value ?? [];
  return activeDevices.any((d) => d.id == deviceId && d.isOnline);
});

/// 单台设备的手机信息概览。
final deviceOverviewProvider = StreamProvider.autoDispose
    .family<DeviceOverview, String>((ref, deviceId) async* {
      // 保持 Provider 活跃，防止 tab 切换时销毁重建导致重新 loading
      ref.keepAlive();

      final service = ref.watch(deviceInfoServiceProvider);
      final registeredDevices = ref.read(deviceRegistryProvider);
      final matchedDevice = registeredDevices.firstWhere(
        (d) => d.id == deviceId,
        orElse: () =>
            RegisteredDevice(id: deviceId, status: 'offline', isOnline: false),
      );

      if (matchedDevice.isHarmony) {
        final cached = await service.loadFromCache(deviceId);
        if (cached != null) {
          yield cached;
        }

        final isOnline = ref.watch(deviceOnlineProvider(deviceId));
        if (!isOnline) {
          if (cached == null) {
            yield DeviceOverview.fromJson({'serial': deviceId});
          }
          return;
        }

        final hdc = ref.read(hdcServiceProvider);
        final paramRes = await hdc.shell(
          deviceId,
          'param get const.ohos.fullname ; param get const.ohos.apiversion ; param get const.product.brand ; param get const.product.model ; param get const.product.name ; param get const.product.software.version ; param get const.product.marketing_name',
        );

        String name = matchedDevice.displayName;
        String brand = 'HUAWEI';
        String model = 'HarmonyOS Device';
        String systemVersion = 'HarmonyOS NEXT';

        if (paramRes.isSuccess && paramRes.stdout.isNotEmpty) {
          final lines = const LineSplitter().convert(paramRes.stdout.trim());
          if (lines.length >= 6) {
            final fullname = lines[0].trim();
            final apiVer = lines[1].trim();
            final devBrand = lines[2].trim();
            final devModel = lines[3].trim();
            final devName = lines[4].trim();
            final devSoft = lines[5].trim();
            final marketingName = lines.length >= 7 ? lines[6].trim() : '';

            if (marketingName.isNotEmpty && !marketingName.contains('fail')) {
              name = marketingName;
            } else if (devName.isNotEmpty && !devName.contains('fail')) {
              name = devName;
            }
            if (devBrand.isNotEmpty && !devBrand.contains('fail')) brand = devBrand;
            if (devModel.isNotEmpty && !devModel.contains('fail')) model = devModel;

            final verSuffix = (devSoft.isNotEmpty && !devSoft.contains('fail')) ? ' ($devSoft)' : '';
            if (fullname.isNotEmpty && !fullname.contains('fail')) {
              systemVersion = '$fullname (API $apiVer)$verSuffix';
            } else {
              systemVersion = 'HarmonyOS NEXT (API $apiVer)$verSuffix';
            }
          }
        }

        // 查询屏幕分辨率与刷新率
        final screenRes = await hdc.shell(deviceId, 'hidumper -s RenderService -a screen');
        String physicalRes = '-';
        String refreshRate = '-';
        if (screenRes.isSuccess && screenRes.stdout.isNotEmpty) {
          final out = screenRes.stdout;
          final resMatch = RegExp(r'physical resolution=([0-9]+x[0-9]+)').firstMatch(out);
          if (resMatch != null) {
            physicalRes = resMatch.group(1) ?? '-';
          }
          final rateMatch = RegExp(r'activeMode: [0-9]+x[0-9]+, refreshRate=([0-9]+)').firstMatch(out);
          if (rateMatch != null) {
            refreshRate = '${rateMatch.group(1)} Hz';
          }
        }

        // 并行获取鸿蒙内存、存储、IP网络、CPU及显示密度
        final results = await Future.wait([
          hdc.shell(deviceId, 'cat /proc/meminfo'),
          hdc.shell(deviceId, 'df -k /data'),
          hdc.shell(deviceId, 'ifconfig wlan0'),
          hdc.shell(deviceId, 'nproc ; uname -m'),
          hdc.shell(deviceId, 'hidumper -s DisplayManagerService -a -a'),
        ]);

        final memRes = results[0];
        final dfRes = results[1];
        final ipRes = results[2];
        final cpuRes = results[3];
        final displayRes = results[4];

        // 1. 内存 (RAM)
        final memInfo = DeviceMemoryInfo.parse(memRes.stdout);
        final memoryTotal = memInfo.total;
        final memoryUsed = memInfo.used;

        // 2. 存储 (Storage: 已用 / 总量)
        String storage = '-';
        if (dfRes.isSuccess && dfRes.stdout.isNotEmpty) {
          final dfLines = dfRes.stdout.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
          if (dfLines.length >= 2) {
            final cols = dfLines.last.split(RegExp(r'\s+'));
            if (cols.length >= 3) {
              final totalKb = int.tryParse(cols[1]);
              final usedKb = int.tryParse(cols[2]);
              if (totalKb != null && usedKb != null) {
                final usedG = (usedKb / 1024 / 1024).toStringAsFixed(2);
                final totalG = (totalKb / 1024 / 1024).toStringAsFixed(2);
                storage = '${usedG}G / ${totalG}G';
              }
            }
          }
        }

        // 3. Wi-Fi 与 IP / MAC 地址
        String ipAddress = '-';
        String macAddress = '-';
        bool wifiEnabled = false;
        String wifi = '-';
        if (ipRes.isSuccess && ipRes.stdout.isNotEmpty) {
          final ip = HdcService.parseIpFromIfconfig(ipRes.stdout);
          if (ip != null && ip.isNotEmpty) {
            ipAddress = ip;
            wifiEnabled = true;
            wifi = 'Connected';
          }
          final mac = HdcService.parseMacFromIfconfig(ipRes.stdout);
          if (mac != null && mac.isNotEmpty) {
            macAddress = mac;
          }
        }

        // 4. 处理器 CPU
        String processor = '-';
        if (cpuRes.isSuccess && cpuRes.stdout.isNotEmpty) {
          final cpuLines = cpuRes.stdout.trim().split('\n');
          final cores = cpuLines.first.trim();
          final arch = cpuLines.length > 1 ? cpuLines[1].trim() : '';
          if (cores.isNotEmpty && int.tryParse(cores) != null) {
            processor = arch.isNotEmpty ? '$cores cores ($arch)' : '$cores cores';
          }
        }

        // 5. 屏幕逻辑密度
        String logicalDensity = '-';
        if (displayRes.isSuccess && displayRes.stdout.isNotEmpty) {
          final densityMatch = RegExp(r'Density:\s*([0-9.]+)').firstMatch(displayRes.stdout);
          if (densityMatch != null) {
            final d = double.tryParse(densityMatch.group(1)!);
            if (d != null) {
              logicalDensity = '${d.toStringAsFixed(2)}x';
            }
          }
        }

        final harmonySerial = ref.read(deviceRegistryProvider.notifier).getSerial(deviceId) ??
            await hdc.getDeviceSerial(deviceId) ??
            deviceId;

        final fresh = DeviceOverview(
          name: name,
          brand: brand,
          model: model,
          serial: harmonySerial,
          androidId: '-',
          androidVersion: systemVersion,
          kernelVersion: 'OpenHarmony',
          processor: processor,
          storage: storage,
          memory: memoryTotal,
          memoryUsed: memoryUsed,
          physicalResolution: physicalRes,
          resolution: physicalRes,
          logicalDensity: logicalDensity,
          refreshRate: refreshRate,
          fontScale: '-',
          wifi: wifi,
          wifiEnabled: wifiEnabled,
          ipAddress: ipAddress,
          macAddress: macAddress,
          airplaneModeEnabled: false,
          mobileDataEnabled: false,
          talkbackEnabled: false,
          windowAnimationScale: '1.0',
          transitionAnimationScale: '1.0',
          animatorDurationScale: '1.0',
          rawResolution: physicalRes,
          hwuiProfile: 'false',
          layoutBoundsEnabled: false,
          showTouchesEnabled: false,
          pointerLocationEnabled: false,
          demoModeEnabled: false,
        );

        // Update system version in device list registry so it registers immediately
        Future.microtask(() {
          if (ref.mounted) {
            final reg = ref.read(deviceRegistryProvider).firstWhere(
              (d) => d.id == deviceId,
              orElse: () => RegisteredDevice(id: deviceId, status: 'offline', isOnline: false),
            );
            if (reg.androidVersion != systemVersion) {
              ref.read(deviceRegistryProvider.notifier).updateDeviceAndroidVersion(deviceId, systemVersion);
            }
            if (reg.model != name && name != deviceId) {
              ref.read(deviceRegistryProvider.notifier).updateDeviceModel(deviceId, name);
            }
          }
        });

        await service.saveToCache(deviceId, fresh);
        yield fresh;
        return;
      }

      if (matchedDevice.isIos) {
        yield DeviceOverview(
          name: matchedDevice.displayName,
          brand: 'Apple',
          model: matchedDevice.model ?? 'iPhone',
          serial: matchedDevice.id,
          androidId: '-',
          androidVersion:
              matchedDevice.androidVersion ??
              (matchedDevice.product != null &&
                      matchedDevice.product!.isNotEmpty
                  ? 'iOS ${matchedDevice.product}'
                  : 'iOS'),
          kernelVersion: 'Darwin',
          processor: '-',
          storage: '-',
          memory: '-',
          physicalResolution: '-',
          resolution: '-',
          logicalDensity: '-',
          refreshRate: '-',
          fontScale: '-',
          wifi: '-',
          wifiEnabled: false,
          ipAddress: '-',
          macAddress: '-',
          airplaneModeEnabled: false,
          mobileDataEnabled: false,
          talkbackEnabled: false,
          windowAnimationScale: '1.0',
          transitionAnimationScale: '1.0',
          animatorDurationScale: '1.0',
          rawResolution: '-',
          hwuiProfile: 'false',
          layoutBoundsEnabled: false,
          showTouchesEnabled: false,
          pointerLocationEnabled: false,
          demoModeEnabled: false,
        );
        return;
      }

      final registryAndroidVersion = ref.watch(
        deviceAndroidVersionProvider(deviceId),
      );

      // 1. 优先尝试从本地持久化缓存加载，以实现零延迟即时展示
      final cached = await service.loadFromCache(deviceId);
      if (!ref.mounted) return;
      if (cached != null) {
        final displayCached = registryAndroidVersion != null
            ? cached.copyWith(androidVersion: registryAndroidVersion)
            : cached;
        if (displayCached.androidVersion != '-' &&
            displayCached.androidVersion.isNotEmpty) {
          Future.microtask(() {
            if (ref.mounted) {
              ref
                  .read(deviceRegistryProvider.notifier)
                  .updateDeviceAndroidVersion(
                    deviceId,
                    displayCached.androidVersion,
                  );
            }
          });
        }
        if (displayCached.ipAddress != '-' &&
            displayCached.ipAddress.isNotEmpty) {
          Future.microtask(() {
            if (ref.mounted) {
              ref
                  .read(deviceRegistryProvider.notifier)
                  .updateDeviceIp(deviceId, displayCached.ipAddress);
            }
          });
        }
        yield displayCached;
      }

      // 检查设备是否在线（使用 ref.watch，以支持响应式状态变化）
      final isOnline = ref.watch(deviceOnlineProvider(deviceId));
      if (!isOnline) {
        if (cached == null) {
          yield DeviceOverview.fromJson({});
        }
        return;
      }

      // 2. 执行 ADB 查询获取最新设备信息并更新
      final fresh = await service.loadOverview(
        deviceId,
        androidVersion: ref.read(deviceAndroidVersionProvider(deviceId)),
      );
      if (!ref.mounted) return;
      if (fresh.androidVersion != '-' && fresh.androidVersion.isNotEmpty) {
        Future.microtask(() {
          if (ref.mounted) {
            ref
                .read(deviceRegistryProvider.notifier)
                .updateDeviceAndroidVersion(deviceId, fresh.androidVersion);
          }
        });
      }
      if (fresh.ipAddress != '-' && fresh.ipAddress.isNotEmpty) {
        Future.microtask(() {
          if (ref.mounted) {
            ref
                .read(deviceRegistryProvider.notifier)
                .updateDeviceIp(deviceId, fresh.ipAddress);
          }
        });
      }
      yield fresh;
    });

/// 单台设备的 adb shell 是否拥有 root 权限。
final isDeviceRootProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  deviceId,
) async {
  final isOnline = ref.watch(deviceOnlineProvider(deviceId));
  if (!isOnline) return false;

  final adb = ref.watch(adbServiceProvider);
  try {
    final result = await adb.shell(deviceId, 'id');
    if (result.isSuccess) {
      return result.stdout.contains('uid=0');
    }
  } catch (_) {}
  return false;
});

/// 离线设备的本地手机信息概览缓存。
final cachedDeviceOverviewProvider = FutureProvider.autoDispose
    .family<DeviceOverview?, String>((ref, deviceId) {
      return ref.watch(deviceInfoServiceProvider).loadFromCache(deviceId);
    });

/// 按设备 and 路径缓存的远程目录内容。
final remoteFilesProvider = FutureProvider.autoDispose
    .family<List<RemoteFile>, RemoteDirectoryRequest>((ref, request) async {
      final isOnline = ref.watch(deviceOnlineProvider(request.deviceId));
      if (!isOnline) {
        return <RemoteFile>[];
      }
      return ref
          .watch(fileManagerServiceProvider)
          .listFiles(request.deviceId, request.path);
    });

/// 文件浏览器当前远程路径。
final remotePathProvider = NotifierProvider<RemotePathNotifier, String>(
  RemotePathNotifier.new,
);

/// 文件浏览器高级导航状态。
final fileNavigationProvider =
    NotifierProvider<FileNavigationNotifier, FileNavigationState>(
      FileNavigationNotifier.new,
    );

/// 文件列表搜索过滤。
final fileFilterQueryProvider =
    NotifierProvider<FileFilterQueryNotifier, String>(
      FileFilterQueryNotifier.new,
    );

/// Logcat 进程控制器和可见日志状态。
final logcatControllerProvider =
    NotifierProvider<LogcatController, LogcatState>(LogcatController.new);

/// 当前选中的 dashboard 工具 tab 下标。
final selectedToolTabProvider = NotifierProvider<ToolTabNotifier, int>(
  ToolTabNotifier.new,
);

/// workspace 面板当前选中的 adb 设备。
final selectedDeviceProvider =
    NotifierProvider<SelectedDeviceNotifier, AdbDevice?>(
      SelectedDeviceNotifier.new,
    );

/// 当前选中的应用包名。
final selectedAppPackageProvider =
    NotifierProvider<SelectedAppPackageNotifier, String?>(
      SelectedAppPackageNotifier.new,
    );

class SelectedAppPackageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  @override
  set state(String? value) => super.state = value;
}

/// 用户是否手动清空了选中的设备（例如点击了 logo）
final userClearedDeviceSelectionProvider =
    NotifierProvider<UserClearedDeviceSelectionNotifier, bool>(
      UserClearedDeviceSelectionNotifier.new,
    );

class UserClearedDeviceSelectionNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

/// 以生成的 session id 为 key 的活跃 scrcpy 会话。
final scrcpySessionsProvider =
    NotifierProvider<ScrcpySessionsNotifier, Map<String, ScrcpySession>>(
      ScrcpySessionsNotifier.new,
    );

/// 保存当前选中的设备。
class SelectedDeviceNotifier extends Notifier<AdbDevice?> {
  @override
  AdbDevice? build() => null;

  /// 从左侧设备列表中选择设备。
  void select(AdbDevice device) {
    final old = state;
    if (old != null && old.id != device.id) {
      ref.read(webDebugServiceProvider).removeForwards(old.id);
    }
    ref.read(selectedAppPackageProvider.notifier).state = null;
    state = device;
  }

  /// 清空选择，使 workspace 不展示具体设备。
  void clear() {
    final old = state;
    if (old != null) {
      ref.read(webDebugServiceProvider).removeForwards(old.id);
    }
    ref.read(selectedAppPackageProvider.notifier).state = null;
    state = null;
  }
}

/// 在 Riverpod 状态中跟踪 scrcpy 会话，供 dashboard 渲染。
class ScrcpySessionsNotifier extends Notifier<Map<String, ScrcpySession>> {
  @override
  Map<String, ScrcpySession> build() => {};

  /// 添加新启动的 scrcpy 会话。
  void add(ScrcpySession session) {
    state = {...state, session.id: session};
  }

  /// 背后进程停止后移除对应会话。
  void removeAll(Iterable<String> sessionIds) {
    final next = Map<String, ScrcpySession>.of(state);
    for (final id in sessionIds) {
      next.remove(id);
    }
    state = next;
  }
}

/// 保存当前工具 tab，避免响应式布局重建时丢失选择。
class ToolTabNotifier extends Notifier<int> {
  @override
  int build() => -1;

  /// 按 TabBar 下标选择 tab。
  /// 旧索引 8（布局分析）归一到 9（截图录屏）。
  void select(int index) {
    state = (index == 8) ? 9 : index;
  }
}

/// 文件导航状态。
class FileNavigationState {
  const FileNavigationState({
    required this.currentPath,
    required this.history,
    required this.historyIndex,
    this.isEditingPath = false,
    this.showHiddenFiles = false,
    this.isGridView = false,
    this.sortColumn = 'name',
    this.sortAscending = true,
  });

  final String currentPath;
  final List<String> history;
  final int historyIndex;
  final bool isEditingPath;
  final bool showHiddenFiles;
  final bool isGridView;
  final String sortColumn;
  final bool sortAscending;

  bool get canGoBack => historyIndex > 0;
  bool get canGoForward => historyIndex < history.length - 1;

  FileNavigationState copyWith({
    String? currentPath,
    List<String>? history,
    int? historyIndex,
    bool? isEditingPath,
    bool? showHiddenFiles,
    bool? isGridView,
    String? sortColumn,
    bool? sortAscending,
  }) {
    return FileNavigationState(
      currentPath: currentPath ?? this.currentPath,
      history: history ?? this.history,
      historyIndex: historyIndex ?? this.historyIndex,
      isEditingPath: isEditingPath ?? this.isEditingPath,
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      isGridView: isGridView ?? this.isGridView,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

/// 维护高级文件浏览器导航状态。
class FileNavigationNotifier extends Notifier<FileNavigationState> {
  @override
  FileNavigationState build() {
    const initialPath = '/';
    return const FileNavigationState(
      currentPath: initialPath,
      history: [initialPath],
      historyIndex: 0,
    );
  }

  void navigateTo(String path) {
    final normalized = _normalize(path);
    if (state.currentPath == normalized) return;

    final newHistory = state.history.sublist(0, state.historyIndex + 1);
    newHistory.add(normalized);

    state = state.copyWith(
      currentPath: normalized,
      history: newHistory,
      historyIndex: newHistory.length - 1,
      isEditingPath: false,
    );
  }

  void goBack() {
    if (!state.canGoBack) return;
    final newIndex = state.historyIndex - 1;
    state = state.copyWith(
      currentPath: state.history[newIndex],
      historyIndex: newIndex,
      isEditingPath: false,
    );
  }

  void goForward() {
    if (!state.canGoForward) return;
    final newIndex = state.historyIndex + 1;
    state = state.copyWith(
      currentPath: state.history[newIndex],
      historyIndex: newIndex,
      isEditingPath: false,
    );
  }

  void goUp() {
    final path = state.currentPath;
    if (path == '/') return;

    final normalized = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final lastSlash = normalized.lastIndexOf('/');
    final parent = lastSlash == 0
        ? '/'
        : normalized.substring(0, lastSlash + 1);

    navigateTo(parent);
  }

  void setEditingPath(bool editing) {
    state = state.copyWith(isEditingPath: editing);
  }

  void toggleShowHiddenFiles() {
    state = state.copyWith(showHiddenFiles: !state.showHiddenFiles);
  }

  void setGridView(bool gridView) {
    state = state.copyWith(isGridView: gridView);
  }

  void toggleSort(String column) {
    if (state.sortColumn == column) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(sortColumn: column, sortAscending: true);
    }
  }

  void setSort(String column, bool ascending) {
    state = state.copyWith(sortColumn: column, sortAscending: ascending);
  }

  String _normalize(String path) {
    var p = path.trim();
    if (!p.startsWith('/')) {
      p = '/$p';
    }
    return p.endsWith('/') ? p : '$p/';
  }
}

/// 维护文件浏览器当前远程目录（兼容层，桥接到 fileNavigationProvider）。
class RemotePathNotifier extends Notifier<String> {
  @override
  String build() {
    return ref.watch(fileNavigationProvider).currentPath;
  }

  /// 打开当前路径下的子目录。
  void open(String folderName) {
    ref
        .read(fileNavigationProvider.notifier)
        .navigateTo(_join(state, folderName));
  }

  /// 返回父目录。
  void back() {
    ref.read(fileNavigationProvider.notifier).goUp();
  }

  /// 替换当前路径。
  void setPath(String path) {
    ref.read(fileNavigationProvider.notifier).navigateTo(path);
  }

  String _join(String base, String child) {
    final normalizedBase = base.endsWith('/') ? base : '$base/';
    return '$normalizedBase$child/';
  }
}

/// 维护文件列表过滤查询。
class FileFilterQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String query) {
    state = query;
  }
}

/// 目录列表 FutureProvider family 使用的 key 对象。
class RemoteDirectoryRequest {
  const RemoteDirectoryRequest({required this.deviceId, required this.path});

  final String deviceId;
  final String path;

  @override
  bool operator ==(Object other) {
    return other is RemoteDirectoryRequest &&
        other.deviceId == deviceId &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(deviceId, path);
}

/// Combined device registry model.
class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    this.customName,
    required this.status,
    this.model,
    this.product,
    this.transportId,
    required this.isOnline,
    this.isChecked = false,
    this.connections = const [],
    this.serial,
    this.ipAddress,
    this.androidVersion,
    this.sdkVersion,
    this.isIos = false,
    this.isHarmony = false,
    this.remark,
    this.tags = const [],
  });

  final String id;
  final String? customName;
  final String status;
  final String? model;
  final String? product;
  final String? transportId;
  final bool isOnline;
  final bool isChecked;
  final List<String> connections;
  final String? serial;
  final String? ipAddress;
  final String? androidVersion;
  final int? sdkVersion;
  final bool isIos;
  final bool isHarmony;
  final String? remark;
  final List<String> tags;

  bool get isNetwork =>
      id.contains(':') || id.contains('.') || id == '127.0.0.1';

  String? get wifiIp {
    if (ipAddress != null && ipAddress!.isNotEmpty && ipAddress != '-') {
      return ipAddress;
    }
    if (isNetwork) {
      final parts = id.split(':');
      if (parts.isNotEmpty) {
        return parts.first;
      }
    }
    return null;
  }

  String get displayName {
    if (customName != null && customName!.isNotEmpty) {
      return customName!;
    }
    if (model != null &&
        model!.isNotEmpty &&
        !model!.toLowerCase().contains('fail')) {
      return model!.replaceAll('_', ' ');
    }
    return id;
  }

  String get connectionMethodDisplay {
    final hasValidModel = model != null &&
        model!.isNotEmpty &&
        !model!.toLowerCase().contains('fail');
    final name = hasValidModel ? model!.replaceAll('_', ' ') : id;
    // 鸿蒙设备 serial 与 id 相同（HDC Device ID），不重复追加
    if (serial != null &&
        serial!.isNotEmpty &&
        serial != id &&
        !serial!.toLowerCase().contains('fail')) {
      return '$name($serial)';
    }
    return name;
  }

  AdbDevice get toAdbDevice => AdbDevice(
    id: id,
    status: status,
    model: model,
    product: product,
    transportId: transportId,
    isIos: isIos,
    isHarmony: isHarmony,
  );

  RegisteredDevice copyWith({
    String? id,
    String? customName,
    String? status,
    String? model,
    String? product,
    String? transportId,
    bool? isOnline,
    bool? isChecked,
    List<String>? connections,
    String? serial,
    String? ipAddress,
    String? androidVersion,
    int? sdkVersion,
    bool? isIos,
    bool? isHarmony,
    String? remark,
    List<String>? tags,
  }) {
    return RegisteredDevice(
      id: id ?? this.id,
      customName: customName ?? this.customName,
      status: status ?? this.status,
      model: model ?? this.model,
      product: product ?? this.product,
      transportId: transportId ?? this.transportId,
      isOnline: isOnline ?? this.isOnline,
      isChecked: isChecked ?? this.isChecked,
      connections: connections ?? this.connections,
      serial: serial ?? this.serial,
      ipAddress: ipAddress ?? this.ipAddress,
      androidVersion: androidVersion ?? this.androidVersion,
      sdkVersion: sdkVersion ?? this.sdkVersion,
      isIos: isIos ?? this.isIos,
      isHarmony: isHarmony ?? this.isHarmony,
      remark: remark ?? this.remark,
      tags: tags ?? this.tags,
    );
  }
}

/// Global device registry provider.
final deviceRegistryProvider =
    NotifierProvider<DeviceRegistryNotifier, List<RegisteredDevice>>(
      DeviceRegistryNotifier.new,
    );

/// 全局设备 Android 版本字符串，格式如 `Android 10 (API 29)`。
final deviceAndroidVersionProvider = Provider.autoDispose
    .family<String?, String>((ref, deviceId) {
      final devices = ref.watch(deviceRegistryProvider);
      for (final device in devices) {
        if (device.id == deviceId ||
            device.serial == deviceId ||
            device.connections.contains(deviceId)) {
          return device.androidVersion;
        }
      }
      return null;
    });

/// 全局设备 SDK 版本号，供投屏、备份、音量等逻辑直接判断系统能力。
final deviceSdkVersionProvider = Provider.autoDispose.family<int?, String>((
  ref,
  deviceId,
) {
  final devices = ref.watch(deviceRegistryProvider);
  for (final device in devices) {
    if (device.id == deviceId ||
        device.serial == deviceId ||
        device.connections.contains(deviceId)) {
      return device.sdkVersion;
    }
  }
  return null;
});

class DeviceRegistryNotifier extends Notifier<List<RegisteredDevice>> {
  static const _historyKey = 'devices.history';
  static const _aliasesKey = 'devices.aliases';
  static const _modelsKey = 'devices.models';
  static const _productsKey = 'devices.products';
  static const _ipsKey = 'devices.ips';
  static const _androidVersionsKey = 'devices.androidVersions';
  static const _sdkVersionsKey = 'devices.sdkVersions';
  static const _remarksKey = 'devices.remarks';
  static const _tagsKey = 'devices.tags';

  List<String> _historyIds = [];
  Map<String, String> _aliases = {};
  Map<String, String> _models = {};
  Map<String, String> _products = {};
  Map<String, String> _ipAddresses = {};
  Map<String, String> _androidVersions = {};
  Map<String, int> _sdkVersions = {};
  Map<String, String> _remarks = {};
  Map<String, List<String>> _tags = {};
  Set<String> _checkedIds = {};
  Map<String, String> _serialMap = {};
  List<AdbDevice> _lastActiveDevices = [];
  final Set<String> _pendingFetchIds = {};
  final Set<String> _attemptedFetchIds = {};
  bool _isDisposed = false;

  /// 获取设备已映射的物理硬件序列号，未映射时返回 null
  String? getSerial(String id) => _serialMap[id];

  bool _isNetworkId(String id) {
    return id.contains(':') || id.contains('.') || id == '127.0.0.1';
  }

  String _getFallbackSerial(String id) {
    if (id.startsWith('adb-') && id.contains('._adb-tls-connect')) {
      final namePart = id.substring(4, id.indexOf('._adb-tls-connect'));
      if (namePart.contains('-')) {
        final lastIndex = namePart.lastIndexOf('-');
        return namePart.substring(0, lastIndex);
      }
      return namePart;
    }
    return id;
  }

  @override
  List<RegisteredDevice> build() {
    ref.onDispose(() {
      _isDisposed = true;
    });

    final activeDevicesAsync = ref.watch(devicesProvider);
    final activeDevices = activeDevicesAsync.value ?? _lastActiveDevices;
    if (activeDevicesAsync.hasValue) {
      _lastActiveDevices = activeDevices;
    }

    _loadFromPrefs();

    return _mergeDevices(activeDevices);
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    final aliasesJson = prefs.getString(_aliasesKey);
    Map<String, String> aliases = {};
    if (aliasesJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(aliasesJson));
        aliases = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final modelsJson = prefs.getString(_modelsKey);
    Map<String, String> models = {};
    if (modelsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(modelsJson));
        models = decoded.map((key, value) => MapEntry(key, value.toString()))
          ..removeWhere((_, value) => value.toLowerCase().contains('fail'));
      } catch (_) {}
    }

    final productsJson = prefs.getString(_productsKey);
    Map<String, String> products = {};
    if (productsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(productsJson));
        products = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final ipsJson = prefs.getString(_ipsKey);
    Map<String, String> ips = {};
    if (ipsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(ipsJson));
        ips = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final androidVersionsJson = prefs.getString(_androidVersionsKey);
    Map<String, String> androidVersions = {};
    if (androidVersionsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(androidVersionsJson),
        );
        androidVersions = decoded.map(
          (key, value) => MapEntry(key, value.toString()),
        );
      } catch (_) {}
    }

    final sdkVersionsJson = prefs.getString(_sdkVersionsKey);
    Map<String, int> sdkVersions = {};
    if (sdkVersionsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(sdkVersionsJson));
        sdkVersions = decoded.map(
          (key, value) => MapEntry(key, int.tryParse(value.toString()) ?? 0),
        )..removeWhere((_, value) => value <= 0);
      } catch (_) {}
    }

    final remarksJson = prefs.getString(_remarksKey);
    Map<String, String> remarks = {};
    if (remarksJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(remarksJson));
        remarks = decoded.map((key, value) => MapEntry(key, value.toString()));
      } catch (_) {}
    }

    final tagsJson = prefs.getString(_tagsKey);
    Map<String, List<String>> tags = {};
    if (tagsJson != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(tagsJson));
        tags = decoded.map((key, value) => MapEntry(key, List<String>.from(value)));
      } catch (_) {}
    }

    if (_isDisposed) return;
    final activeDevices = _lastActiveDevices;

    // 清洗因历史 ADB track-devices 协议解析漏洞产生的被十六进制长度前缀污染的脏设备 ID
    String stripHexPrefix(String rawId) {
      // iOS UDID（40 位纯十六进制或 25 位带中划线）绝不能被误判为十六进制长度前缀剥离
      if (rawId.length == 40 && !rawId.contains(RegExp(r'[^a-fA-F0-9]'))) {
        return rawId;
      }
      if (rawId.length == 25 && rawId.indexOf('-') == 8) {
        return rawId;
      }

      var current = rawId;
      // 每次剥离 4 字符十六进制长度包头，直到无法剥离或达到合理最小长度
      while (current.length > 8) {
        final prefix = current.substring(0, 4);
        if (int.tryParse(prefix, radix: 16) != null) {
          final candidate = current.substring(4);
          if (history.contains(candidate) ||
              activeDevices.any((d) => d.id == candidate) ||
              candidate.startsWith('adb-')) {
            current = candidate;
            continue;
          }
        }
        break;
      }
      return current;
    }

    final cleanedHistory = <String>[];
    bool historyPolluted = false;
    for (final id in history) {
      final realId = stripHexPrefix(id);
      if (realId != id) {
        historyPolluted = true;
        // 将脏 ID 上的缓存元数据迁移给真实 realId
        if (aliases.containsKey(id) && !aliases.containsKey(realId)) {
          aliases[realId] = aliases[id]!;
        }
        if (models.containsKey(id) && !models.containsKey(realId)) {
          models[realId] = models[id]!;
        }
        if (products.containsKey(id) && !products.containsKey(realId)) {
          products[realId] = products[id]!;
        }
        if (ips.containsKey(id) && !ips.containsKey(realId)) {
          ips[realId] = ips[id]!;
        }
        if (androidVersions.containsKey(id) && !androidVersions.containsKey(realId)) {
          androidVersions[realId] = androidVersions[id]!;
        }
        if (sdkVersions.containsKey(id) && !sdkVersions.containsKey(realId)) {
          sdkVersions[realId] = sdkVersions[id]!;
        }
        if (remarks.containsKey(id) && !remarks.containsKey(realId)) {
          remarks[realId] = remarks[id]!;
        }
        if (tags.containsKey(id) && !tags.containsKey(realId)) {
          tags[realId] = tags[id]!;
        }

        aliases.remove(id);
        models.remove(id);
        products.remove(id);
        ips.remove(id);
        androidVersions.remove(id);
        sdkVersions.remove(id);
        remarks.remove(id);
        tags.remove(id);

        if (!cleanedHistory.contains(realId)) {
          cleanedHistory.add(realId);
        }
      } else {
        if (!cleanedHistory.contains(id)) {
          cleanedHistory.add(id);
        }
      }
    }

    // 自动清理与合并此前被历史 stripHexPrefix 截断为 8 位的残缺 iOS 设备记录，合并回完整 UDID
    final candidateFullUdids = <String>{
      ...activeDevices.map((d) => d.id),
      ...tags.keys,
      ...remarks.keys,
      ...history,
    };
    for (final fullUdid in candidateFullUdids) {
      if (fullUdid.length == 40 && !fullUdid.contains(RegExp(r'[^a-fA-F0-9]'))) {
        final suffix = fullUdid.substring(32); // 取后 8 位残缺 ID
        if (cleanedHistory.contains(suffix) || history.contains(suffix)) {
          historyPolluted = true;
          cleanedHistory.remove(suffix);
          history.remove(suffix);

          // 将被截断残缺 ID 上的备注、别名、标签合并回完整真实 UDID
          if (remarks.containsKey(suffix) && !remarks.containsKey(fullUdid)) {
            remarks[fullUdid] = remarks[suffix]!;
          }
          if (aliases.containsKey(suffix) && !aliases.containsKey(fullUdid)) {
            aliases[fullUdid] = aliases[suffix]!;
          }
          if (tags.containsKey(suffix) && !tags.containsKey(fullUdid)) {
            tags[fullUdid] = tags[suffix]!;
          }

          remarks.remove(suffix);
          aliases.remove(suffix);
          tags.remove(suffix);
          models.remove(suffix);
          products.remove(suffix);
        }
      }
    }

    if (historyPolluted) {
      history.clear();
      history.addAll(cleanedHistory);
      prefs.setStringList(_historyKey, cleanedHistory);
      prefs.setString(_remarksKey, jsonEncode(remarks));
      prefs.setString(_tagsKey, jsonEncode(tags));
      prefs.setString(_modelsKey, jsonEncode(models));
      prefs.setString(_productsKey, jsonEncode(products));
    }

    _historyIds = history;
    _aliases = aliases;
    _models = models;
    _products = products;
    _androidVersions = androidVersions;
    _sdkVersions = sdkVersions;
    _remarks = remarks;
    _tags = tags;

    // 加载缓存的序列号映射
    final allIds = {...history, ...activeDevices.map((d) => d.id)};
    final serialMap = <String, String>{};
    for (final id in allIds) {
      final jsonStr = prefs.getString('devices.overview.$id');
      if (jsonStr != null) {
        try {
          final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
          final cachedVersion = decoded['androidVersion']?.toString();
          if (cachedVersion != null &&
              cachedVersion.isNotEmpty &&
              cachedVersion != '-') {
            androidVersions[id] = cachedVersion;
            final cachedSdk = _parseSdkVersion(cachedVersion);
            if (cachedSdk != null) {
              sdkVersions[id] = cachedSdk;
            }
          }
          final cachedIp = decoded['ipAddress']?.toString();
          if (cachedIp != null && cachedIp.isNotEmpty && cachedIp != '-') {
            ips[id] ??= cachedIp;
          }
          final cachedName = decoded['name']?.toString();
          final cachedModel = decoded['model']?.toString();
          final realName = (cachedName != null && !_isGenericHarmonyModel(cachedName))
              ? cachedName
              : ((cachedModel != null && !_isGenericHarmonyModel(cachedModel))
                  ? cachedModel
                  : null);
          if (realName != null) {
            if (models[id] == null || _isGenericHarmonyModel(models[id])) {
              models[id] = realName;
            }
          }
        } catch (_) {}
      }

      if (!_isNetworkId(id)) {
        serialMap[id] = id;
      } else {
        var serial = _getFallbackSerial(id);
        if (serial != id) {
          serialMap[id] = serial;
        }

        if (jsonStr != null) {
          try {
            final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
            final cachedSerial = decoded['serial']?.toString();
            if (cachedSerial != null &&
                cachedSerial.isNotEmpty &&
                cachedSerial != '-') {
              serialMap[id] = cachedSerial;
              final cachedVersion = androidVersions[id];
              if (cachedVersion != null && cachedVersion.isNotEmpty) {
                androidVersions[cachedSerial] = cachedVersion;
              }
              final cachedSdk = sdkVersions[id];
              if (cachedSdk != null) {
                sdkVersions[cachedSerial] = cachedSdk;
              }
            }
            final cachedIp = decoded['ipAddress']?.toString();
            if (cachedIp != null && cachedIp.isNotEmpty && cachedIp != '-') {
              ips[id] = cachedIp;
            }
          } catch (_) {}
        }
      }
    }

    // 智能处理历史离线设备中的网络记录（如鸿蒙 Wi-Fi 设备）：
    // 若网络设备缓存的 serial 仍是网络 ID 本身，尝试通过 IP 地址与同一平台/型号匹配历史物理硬件设备
    for (final id in allIds) {
      if (!_isNetworkId(id)) continue;
      final currentSerial = serialMap[id];
      if (currentSerial == null || _isNetworkId(currentSerial)) {
        final devIp = ips[id] ??
            (id.contains(':')
                ? id.split(':').first
                : (id.contains('.') ? id : null));
        if (devIp == null || devIp.isEmpty || devIp == '127.0.0.1') continue;

        for (final usbId in allIds) {
          if (_isNetworkId(usbId)) continue;
          final usbIp = ips[usbId];
          final sameIp = usbIp == devIp;
          final isSameHarmony =
              products[id] == 'HarmonyOS NEXT' && products[usbId] == 'HarmonyOS NEXT';
          final isSameModel =
              models[id] != null &&
              models[id]!.isNotEmpty &&
              models[id] == models[usbId];

          if (sameIp && (isSameHarmony || isSameModel)) {
            serialMap[id] = usbId;
            final cachedVersion = androidVersions[id];
            if (cachedVersion != null && cachedVersion.isNotEmpty) {
              androidVersions[usbId] ??= cachedVersion;
            }
            final cachedSdk = sdkVersions[id];
            if (cachedSdk != null && cachedSdk > 0) {
              sdkVersions[usbId] ??= cachedSdk;
            }

            // 更新 SharedPreferences 中关于网络设备的 overview 缓存中的 serial 字段
            final overviewKey = 'devices.overview.$id';
            final cachedJson = prefs.getString(overviewKey);
            if (cachedJson != null) {
              try {
                final map = Map<String, dynamic>.from(jsonDecode(cachedJson));
                map['serial'] = usbId;
                prefs.setString(overviewKey, jsonEncode(map));
              } catch (_) {}
            }
            break;
          }
        }
      }
    }
    _serialMap = serialMap;
    _ipAddresses = ips;

    state = _mergeDevices(activeDevices);
  }

  void _fetchAndCacheSerial(String id) {
    Future.microtask(() async {
      final activeDevs = ref.read(devicesProvider).value ?? _lastActiveDevices;
      final dev = activeDevs.firstWhere((d) => d.id == id, orElse: () => AdbDevice(id: id, status: 'offline', model: '', product: ''));
      if (dev.isHarmony) {
        _fetchAndCacheHarmony(id);
        return;
      }

      try {
        final adb = ref.read(adbServiceProvider);
        final androidVersion = await _fetchAndroidVersion(id);
        if (androidVersion != null) {
          _cacheAndroidVersion(id, androidVersion.label, androidVersion.sdk);
          await _saveAndroidVersions();
          if (!_isDisposed) {
            final activeDevices =
                ref.read(devicesProvider).value ?? _lastActiveDevices;
            state = _mergeDevices(activeDevices);
          }
        }

        // Try shell getprop ro.serialno first as it returns the real hardware serial number for wireless/network devices.
        var result = await adb.shellArgs(id, ['getprop', 'ro.serialno']);
        if (_isDisposed) return;

        var serial = result.isSuccess ? result.stdout.trim() : '';
        if (serial.isEmpty || serial == 'unknown' || serial == '-') {
          final bootResult = await adb.shellArgs(id, [
            'getprop',
            'ro.boot.serialno',
          ]);
          if (_isDisposed) return;
          serial = bootResult.isSuccess ? bootResult.stdout.trim() : '';
        }

        if (serial.isEmpty || serial == 'unknown' || serial == '-') {
          final getSerialResult = await adb.run(['-s', id, 'get-serialno']);
          if (_isDisposed) return;
          serial = getSerialResult.isSuccess
              ? getSerialResult.stdout.trim()
              : '';
        }

        if (serial.isNotEmpty && serial != 'unknown' && serial != '-') {
          _serialMap[id] = serial;
          final cachedVersion = _androidVersions[id];
          final cachedSdk = _sdkVersions[id];
          if (cachedVersion != null && cachedSdk != null) {
            _cacheAndroidVersion(id, cachedVersion, cachedSdk);
          }

          final prefs = await SharedPreferences.getInstance();
          final cacheKey = 'devices.overview.$id';
          final existingJson = prefs.getString(cacheKey);
          DeviceOverview overview;
          if (existingJson != null) {
            try {
              final decoded = jsonDecode(existingJson) as Map<String, dynamic>;
              overview = DeviceOverview.fromJson(
                decoded,
              ).copyWith(serial: serial);
            } catch (_) {
              overview = DeviceOverview(
                name: id,
                brand: '-',
                model: '-',
                serial: serial,
                androidId: '-',
                androidVersion: '-',
                kernelVersion: '-',
                processor: '-',
                storage: '-',
                memory: '-',
                physicalResolution: '-',
                resolution: '-',
                logicalDensity: '-',
                refreshRate: '-',
                fontScale: '-',
                wifi: '-',
                wifiEnabled: false,
                ipAddress: '-',
                macAddress: '-',
                airplaneModeEnabled: false,
                mobileDataEnabled: false,
                talkbackEnabled: false,
                windowAnimationScale: '1.0',
                transitionAnimationScale: '1.0',
                animatorDurationScale: '1.0',
                rawResolution: '-',
                hwuiProfile: 'false',
                layoutBoundsEnabled: false,
                showTouchesEnabled: false,
                pointerLocationEnabled: false,
                demoModeEnabled: false,
              );
            }
          } else {
            overview = DeviceOverview(
              name: id,
              brand: '-',
              model: '-',
              serial: serial,
              androidId: '-',
              androidVersion: '-',
              kernelVersion: '-',
              processor: '-',
              storage: '-',
              memory: '-',
              physicalResolution: '-',
              resolution: '-',
              logicalDensity: '-',
              refreshRate: '-',
              fontScale: '-',
              wifi: '-',
              wifiEnabled: false,
              ipAddress: '-',
              macAddress: '-',
              airplaneModeEnabled: false,
              mobileDataEnabled: false,
              talkbackEnabled: false,
              windowAnimationScale: '1.0',
              transitionAnimationScale: '1.0',
              animatorDurationScale: '1.0',
              rawResolution: '-',
              hwuiProfile: 'false',
              layoutBoundsEnabled: false,
              showTouchesEnabled: false,
              pointerLocationEnabled: false,
              demoModeEnabled: false,
            );
          }
          await prefs.setString(cacheKey, jsonEncode(overview.toJson()));
        } else {
          _serialMap[id] = id;
        }

        // 如果不是网络连接设备，获取并缓存其 IP 地址
        if (!_isNetworkId(id)) {
          final ip = await _fetchDeviceIpAddress(id);
          if (ip != null && ip.isNotEmpty) {
            _ipAddresses[id] = ip;
            final currentSerial = _serialMap[id] ?? id;
            if (currentSerial != id) {
              _ipAddresses[currentSerial] = ip;
            }
            await _saveIps();
          } else {
            _ipAddresses[id] = '-';
            final currentSerial = _serialMap[id] ?? id;
            if (currentSerial != id) {
              _ipAddresses[currentSerial] = '-';
            }
            await _saveIps();
          }
        }
      } catch (_) {
        _serialMap[id] = id;
      } finally {
        _pendingFetchIds.remove(id);
        _attemptedFetchIds.add(id);
        if (!_isDisposed) {
          final activeDevices =
              ref.read(devicesProvider).value ?? _lastActiveDevices;
          state = _mergeDevices(activeDevices);
        }
      }
    });
  }

  bool _isGenericHarmonyModel(String? s) {
    if (s == null || s.isEmpty) return true;
    final lower = s.toLowerCase().trim();
    return lower == 'harmonyos device' ||
        lower == 'harmonyos next device' ||
        lower.startsWith('harmonyos device') ||
        lower.startsWith('harmonyos next') ||
        lower == 'openharmony' ||
        lower.contains('fail');
  }

  void _fetchAndCacheHarmony(String id) {
    Future.microtask(() async {
      try {
        final hdc = ref.read(hdcServiceProvider);
        final paramRes = await hdc.shell(
          id,
          'param get const.ohos.fullname ; param get const.ohos.apiversion ; param get const.product.brand ; param get const.product.model ; param get const.product.name ; param get const.product.software.version ; param get const.product.marketing_name',
        );
        if (_isDisposed) return;

        String systemVersion = 'HarmonyOS NEXT';
        int sdkVersion = 23; // 默认 API 23
        String deviceName = '';

        if (paramRes.isSuccess && paramRes.stdout.isNotEmpty) {
          final lines = const LineSplitter().convert(paramRes.stdout.trim());
          if (lines.length >= 2) {
            final fullname = lines[0].trim();
            final apiVerStr = lines[1].trim();
            final parsedApi = int.tryParse(apiVerStr) ?? 0;
            if (parsedApi > 0) {
              sdkVersion = parsedApi;
            }
            if (fullname.isNotEmpty && !fullname.toLowerCase().contains('fail')) {
              systemVersion = '$fullname (API $sdkVersion)';
            } else {
              systemVersion = 'HarmonyOS NEXT (API $sdkVersion)';
            }
          }
          bool isValidName(String s) =>
              s.isNotEmpty && !s.toLowerCase().contains('fail');

          if (lines.length >= 7 && isValidName(lines[6].trim())) {
            deviceName = lines[6].trim();
          } else if (lines.length >= 5 && isValidName(lines[4].trim())) {
            deviceName = lines[4].trim();
          } else if (lines.length >= 4 && isValidName(lines[3].trim())) {
            deviceName = lines[3].trim();
          }
        }

        // 获取鸿蒙设备真实物理序列号
        final rawSerial = await hdc.getDeviceSerial(id);
        if (_isDisposed) return;
        final serial = (rawSerial != null && rawSerial.isNotEmpty)
            ? rawSerial
            : (!_isNetworkId(id) ? id : null);

        if (serial != null && serial.isNotEmpty) {
          _serialMap[id] = serial;
          if (!_isNetworkId(serial)) {
            _serialMap[serial] = serial;
          }
        } else {
          _serialMap[id] = id;
        }

        final effectiveSerial = _serialMap[id] ?? id;
        _androidVersions[id] = systemVersion;
        _sdkVersions[id] = sdkVersion;
        if (effectiveSerial != id) {
          _androidVersions[effectiveSerial] = systemVersion;
          _sdkVersions[effectiveSerial] = sdkVersion;
        }
        if (deviceName.isNotEmpty && !_isGenericHarmonyModel(deviceName)) {
          _models[id] = deviceName;
          if (effectiveSerial != id) {
            _models[effectiveSerial] = deviceName;
          }
          await _saveModelsAndProducts();
        }
        await _saveAndroidVersions();

        // 尝试获取 IP 地址与 MAC 地址
        final ifconfigRes = await hdc.shell(id, 'ifconfig');
        if (_isDisposed) return;
        String? harmonyMac;
        if (ifconfigRes.isSuccess && ifconfigRes.stdout.isNotEmpty) {
          final ip = _parseIpFromIfconfig(ifconfigRes.stdout);
          if (ip != null && ip.isNotEmpty) {
            _ipAddresses[id] = ip;
            if (effectiveSerial != id) {
              _ipAddresses[effectiveSerial] = ip;
            }
            await _saveIps();
          }
          harmonyMac = HdcService.parseMacFromIfconfig(ifconfigRes.stdout);
        }

        // 保存 overview 缓存，确保持久化真实 serial
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'devices.overview.$id';
        final existingJson = prefs.getString(cacheKey);
        DeviceOverview overview;
        if (existingJson != null) {
          try {
            final decoded = jsonDecode(existingJson) as Map<String, dynamic>;
            overview = DeviceOverview.fromJson(decoded).copyWith(
              serial: effectiveSerial,
              androidVersion: systemVersion,
              name: deviceName.isNotEmpty ? deviceName : null,
              model: deviceName.isNotEmpty ? deviceName : null,
              ipAddress: _ipAddresses[id],
              macAddress: harmonyMac ?? decoded['macAddress']?.toString(),
            );
          } catch (_) {
            overview = DeviceOverview(
              name: deviceName.isNotEmpty ? deviceName : id,
              brand: 'HUAWEI',
              model: deviceName.isNotEmpty ? deviceName : 'HarmonyOS Device',
              serial: effectiveSerial,
              androidId: '-',
              androidVersion: systemVersion,
              kernelVersion: 'OpenHarmony',
              processor: '-',
              storage: '-',
              memory: '-',
              physicalResolution: '-',
              resolution: '-',
              logicalDensity: '-',
              refreshRate: '-',
              fontScale: '-',
              wifi: '-',
              wifiEnabled: false,
              ipAddress: _ipAddresses[id] ?? '-',
              macAddress: harmonyMac ?? '-',
              airplaneModeEnabled: false,
              mobileDataEnabled: false,
              talkbackEnabled: false,
              windowAnimationScale: '1.0',
              transitionAnimationScale: '1.0',
              animatorDurationScale: '1.0',
              rawResolution: '-',
              hwuiProfile: 'false',
              layoutBoundsEnabled: false,
              showTouchesEnabled: false,
              pointerLocationEnabled: false,
              demoModeEnabled: false,
            );
          }
        } else {
          overview = DeviceOverview(
            name: deviceName.isNotEmpty ? deviceName : id,
            brand: 'HUAWEI',
            model: deviceName.isNotEmpty ? deviceName : 'HarmonyOS Device',
            serial: effectiveSerial,
            androidId: '-',
            androidVersion: systemVersion,
            kernelVersion: 'OpenHarmony',
            processor: '-',
            storage: '-',
            memory: '-',
            physicalResolution: '-',
            resolution: '-',
            logicalDensity: '-',
            refreshRate: '-',
            fontScale: '-',
            wifi: '-',
            wifiEnabled: false,
            ipAddress: _ipAddresses[id] ?? '-',
            macAddress: harmonyMac ?? '-',
            airplaneModeEnabled: false,
            mobileDataEnabled: false,
            talkbackEnabled: false,
            windowAnimationScale: '1.0',
            transitionAnimationScale: '1.0',
            animatorDurationScale: '1.0',
            rawResolution: '-',
            hwuiProfile: 'false',
            layoutBoundsEnabled: false,
            showTouchesEnabled: false,
            pointerLocationEnabled: false,
            demoModeEnabled: false,
          );
        }
        await prefs.setString(cacheKey, jsonEncode(overview.toJson()));
        if (effectiveSerial != id) {
          await prefs.setString(
            'devices.overview.$effectiveSerial',
            jsonEncode(overview.copyWith(serial: effectiveSerial).toJson()),
          );
        }

        if (!_isDisposed) {
          final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
          state = _mergeDevices(activeDevices);
        }
      } catch (_) {
        _serialMap[id] = id;
      } finally {
        _pendingFetchIds.remove(id);
        _attemptedFetchIds.add(id);
        if (!_isDisposed) {
          final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
          state = _mergeDevices(activeDevices);
        }
      }
    });
  }

  String? _parseIpFromIfconfig(String output) {
    final regExp = RegExp(r'inet addr:(\d+\.\d+\.\d+\.\d+)');
    for (final line in output.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final ip = match.group(1);
        if (ip != null && ip != '127.0.0.1') {
          return ip;
        }
      }
    }
    return null;
  }

  Future<({String label, int sdk})?> _fetchAndroidVersion(String id) async {
    try {
      final adb = ref.read(adbServiceProvider);
      final releaseResult = await adb.shellArgs(id, [
        'getprop',
        'ro.build.version.release',
      ]);
      if (_isDisposed) return null;
      final sdkResult = await adb.shellArgs(id, [
        'getprop',
        'ro.build.version.sdk',
      ]);
      if (_isDisposed) return null;

      final release = releaseResult.isSuccess
          ? releaseResult.stdout.trim()
          : '';
      final sdk = sdkResult.isSuccess ? sdkResult.stdout.trim() : '';
      final sdkVersion = int.tryParse(sdk);
      if (release.isEmpty ||
          release == 'unknown' ||
          sdkVersion == null ||
          sdkVersion <= 0) {
        return null;
      }
      return (label: 'Android $release (API $sdkVersion)', sdk: sdkVersion);
    } catch (_) {
      return null;
    }
  }

  int? _parseSdkVersion(String androidVersion) {
    final match = RegExp(r'API\s+(\d+)').firstMatch(androidVersion);
    return match == null ? null : int.tryParse(match.group(1) ?? '');
  }

  void _cacheAndroidVersion(String id, String androidVersion, int sdkVersion) {
    _androidVersions[id] = androidVersion;
    _sdkVersions[id] = sdkVersion;
    final currentSerial = _serialMap[id] ?? id;
    if (currentSerial != id) {
      _androidVersions[currentSerial] = androidVersion;
      _sdkVersions[currentSerial] = sdkVersion;
    }
  }

  Future<String?> _fetchDeviceIpAddress(String id) async {
    // 优先尝试从本设备的概览缓存获取 IP
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'devices.overview.$id';
      final jsonStr = prefs.getString(cacheKey);
      if (jsonStr != null) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        final cachedIp = decoded['ipAddress']?.toString();
        if (cachedIp != null && cachedIp.isNotEmpty && cachedIp != '-') {
          return cachedIp;
        }
      }
    } catch (_) {}

    try {
      final adb = ref.read(adbServiceProvider);
      // 1. 尝试通过 ip route 获取
      final routeResult = await adb.shellArgs(id, ['ip', 'route']);
      if (routeResult.isSuccess) {
        final ip = _parseIpFromIpRoute(routeResult.stdout);
        if (ip != null) return ip;
      }

      // 2. 尝试通过 ip addr show wlan0 获取
      final wlanResult = await adb.shellArgs(id, [
        'ip',
        'addr',
        'show',
        'wlan0',
      ]);
      if (wlanResult.isSuccess) {
        final ip = _parseIpFromIpAddr(wlanResult.stdout);
        if (ip != null) return ip;
      }

      // 3. 尝试通过 ip addr show 兜底获取
      final addrResult = await adb.shellArgs(id, ['ip', 'addr', 'show']);
      if (addrResult.isSuccess) {
        final ip = _parseIpFromIpAddr(addrResult.stdout);
        if (ip != null) return ip;
      }
    } catch (_) {}
    return null;
  }

  String? _parseIpFromIpRoute(String output) {
    final regExp = RegExp(
      r'dev\s+(\S+)\s+.*?\b(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\b',
    );
    for (final line in output.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final ip = match.group(2);
        if (ip != null && ip != '127.0.0.1' && !ip.endsWith('.0')) {
          return ip;
        }
      }
    }
    return null;
  }

  String? _parseIpFromIpAddr(String output) {
    final regExp = RegExp(r'inet\s+(\d+\.\d+\.\d+\.\d+)');
    for (final line in output.split('\n')) {
      final match = regExp.firstMatch(line);
      if (match != null) {
        final ip = match.group(1);
        if (ip != null && ip != '127.0.0.1') {
          return ip;
        }
      }
    }
    return null;
  }

  Future<void> _saveIps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_ipsKey, jsonEncode(_ipAddresses));
    } catch (_) {}
  }

  Future<void> _saveAndroidVersions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_androidVersionsKey, jsonEncode(_androidVersions));
      await prefs.setString(_sdkVersionsKey, jsonEncode(_sdkVersions));
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _historyIds);
  }

  Future<void> _saveAliases() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_aliasesKey, jsonEncode(_aliases));
  }

  Future<void> _saveModelsAndProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelsKey, jsonEncode(_models));
      await prefs.setString(_productsKey, jsonEncode(_products));
    } catch (_) {}
  }

  List<RegisteredDevice> _mergeDevices(List<AdbDevice> activeDevices) {
    final activeMap = {for (final d in activeDevices) d.id: d};

    bool historyChanged = false;
    final nextHistory = List<String>.from(_historyIds);
    for (final device in activeDevices) {
      if (!nextHistory.contains(device.id)) {
        nextHistory.add(device.id);
        historyChanged = true;
      }
    }
    if (historyChanged) {
      _historyIds = nextHistory;
      _saveHistory();
    }

    // 缓存最新获取到的在线设备 model 和 product 信息
    bool modelsOrProductsChanged = false;
    for (final device in activeDevices) {
      if (device.model != null && device.model!.isNotEmpty) {
        if (_models[device.id] != device.model) {
          _models[device.id] = device.model!;
          modelsOrProductsChanged = true;
        }
      }
      if (device.product != null && device.product!.isNotEmpty) {
        if (_products[device.id] != device.product) {
          _products[device.id] = device.product!;
          modelsOrProductsChanged = true;
        }
      }
    }
    if (modelsOrProductsChanged) {
      _saveModelsAndProducts();
    }

    // 触发获取新在线设备(或无缓存的IP/系统版本)的序列号、IP 和 Android 版本。
    final activeIds = activeDevices.map((d) => d.id).toSet();
    _attemptedFetchIds.removeWhere((id) => !activeIds.contains(id));

    for (final device in activeDevices) {
      final hasSerial = _serialMap.containsKey(device.id);
      final isNet = _isNetworkId(device.id);
      final hasIp =
          isNet ||
          (_ipAddresses.containsKey(device.id) &&
              _ipAddresses[device.id] != null &&
              _ipAddresses[device.id] != '-');
      final serial = _serialMap[device.id] ?? device.id;
      final hasAndroidVersion =
          _androidVersions.containsKey(device.id) ||
          _androidVersions.containsKey(serial);
      final hasSdkVersion =
          _sdkVersions.containsKey(device.id) ||
          _sdkVersions.containsKey(serial);
      if (device.isOnline &&
          (!hasSerial || !hasIp || !hasAndroidVersion || !hasSdkVersion) &&
          !_pendingFetchIds.contains(device.id) &&
          !_attemptedFetchIds.contains(device.id)) {
        _pendingFetchIds.add(device.id);
        _fetchAndCacheSerial(device.id);
      }
    }

    final allCandidates = <RegisteredDevice>[];
    for (final id in _historyIds) {
      final active = activeMap[id];
      final customName = _aliases[id];
      final isChecked = _checkedIds.contains(id);
      final serial = _serialMap[id] ?? id;
      final cachedModel = _models[id];
      final cachedProduct = _products[id];
      final ipAddress = _ipAddresses[serial] ?? _ipAddresses[id];
      final androidVersion = _androidVersions[serial] ?? _androidVersions[id];
      final sdkVersion = _sdkVersions[serial] ?? _sdkVersions[id];

      final remark = _remarks[id];
      final tags = _tags[id] ?? [];

      if (active != null) {
        // 对鸿蒙设备，若 active 或 _models 缓存中已有真实设备名（非通用占位符），优先使用真实型号
        String? effectiveModel;
        if (active.isHarmony) {
          if (active.model != null && !_isGenericHarmonyModel(active.model)) {
            effectiveModel = active.model;
          } else if (cachedModel != null && !_isGenericHarmonyModel(cachedModel)) {
            effectiveModel = cachedModel;
          } else {
            effectiveModel = active.model ?? cachedModel;
          }
        } else {
          effectiveModel = active.model ?? cachedModel;
        }
        allCandidates.add(
          RegisteredDevice(
            id: id,
            customName: customName,
            status: active.status,
            model: effectiveModel,
            product: active.product ?? cachedProduct,
            transportId: active.transportId,
            isOnline: active.isOnline,
            isChecked: isChecked,
            connections: [id],
            serial: serial,
            ipAddress: ipAddress,
            androidVersion: androidVersion,
            sdkVersion: sdkVersion,
            isIos: active.isIos,
            isHarmony: active.isHarmony,
            remark: remark,
            tags: tags,
          ),
        );
      } else {
        String? effectiveOfflineModel = cachedModel;
        if (_isGenericHarmonyModel(effectiveOfflineModel)) {
          final sModel = _models[serial];
          if (sModel != null && !_isGenericHarmonyModel(sModel)) {
            effectiveOfflineModel = sModel;
          }
        }
        allCandidates.add(
          RegisteredDevice(
            id: id,
            customName: customName,
            status: 'offline',
            model: effectiveOfflineModel,
            product: cachedProduct,
            isOnline: false,
            isChecked: isChecked,
            connections: [id],
            serial: serial,
            ipAddress: ipAddress,
            androidVersion: androidVersion,
            sdkVersion: sdkVersion,
            remark: remark,
            tags: tags,
            isIos:
                cachedModel != null &&
                (cachedModel.contains('iPhone') ||
                    cachedModel.contains('iPad') ||
                    cachedModel.contains('Apple') ||
                    cachedModel.contains('iOS') ||
                    id.length == 40 ||
                    (id.length == 25 && id.indexOf('-') == 8)),
            isHarmony:
                cachedProduct == 'HarmonyOS NEXT' ||
                (cachedModel != null &&
                    (cachedModel.contains('HarmonyOS') ||
                        cachedModel.contains('HOS'))),
          ),
        );
      }
    }

    // 按序列号分组
    final groups = <String, List<RegisteredDevice>>{};
    for (final candidate in allCandidates) {
      final serial = _serialMap[candidate.id] ?? candidate.id;
      groups.putIfAbsent(serial, () => []).add(candidate);
    }

    // 每个序列号只选出一个最佳候选做代表来进行去重
    final merged = <RegisteredDevice>[];
    groups.forEach((serial, candidates) {
      if (candidates.length == 1) {
        final c = candidates.first;
        final effectiveRemark = (c.remark != null && c.remark!.isNotEmpty)
            ? c.remark
            : (_remarks[serial] ?? _remarks[c.id]);
        final effectiveTags = c.tags.isNotEmpty
            ? c.tags
            : (_tags[serial] ?? _tags[c.id] ?? []);
        merged.add(
          c.copyWith(
            remark: effectiveRemark,
            tags: effectiveTags,
          ),
        );
      } else {
        // 排序规则：在线优先，USB 优先
        candidates.sort((a, b) {
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;

          final aIsUsb = !a.isNetwork;
          final bIsUsb = !b.isNetwork;
          if (aIsUsb && !bIsUsb) return -1;
          if (!aIsUsb && bIsUsb) return 1;

          return a.id.compareTo(b.id);
        });

        final best = candidates.first;
        final anyChecked = candidates.any((c) => c.isChecked);

        String? mergedCustomName;
        for (final c in candidates) {
          if (c.customName != null && c.customName!.isNotEmpty) {
            mergedCustomName = c.customName;
            break;
          }
        }

        String? mergedModel = best.model;
        if (mergedModel == null || mergedModel.isEmpty || _isGenericHarmonyModel(mergedModel)) {
          for (final c in candidates) {
            if (c.model != null && c.model!.isNotEmpty && !_isGenericHarmonyModel(c.model)) {
              mergedModel = c.model;
              break;
            }
          }
        }

        String? mergedProduct = best.product;
        if (mergedProduct == null || mergedProduct.isEmpty) {
          for (final c in candidates) {
            if (c.product != null && c.product!.isNotEmpty) {
              mergedProduct = c.product;
              break;
            }
          }
        }

        String? mergedIp = best.ipAddress;
        if (mergedIp == null || mergedIp.isEmpty || mergedIp == '-') {
          for (final c in candidates) {
            if (c.ipAddress != null &&
                c.ipAddress!.isNotEmpty &&
                c.ipAddress != '-') {
              mergedIp = c.ipAddress;
              break;
            }
          }
        }

        String? mergedAndroidVersion = best.androidVersion;
        if (mergedAndroidVersion == null || mergedAndroidVersion.isEmpty) {
          for (final c in candidates) {
            if (c.androidVersion != null && c.androidVersion!.isNotEmpty) {
              mergedAndroidVersion = c.androidVersion;
              break;
            }
          }
        }

        int? mergedSdkVersion = best.sdkVersion;
        if (mergedSdkVersion == null) {
          for (final c in candidates) {
            if (c.sdkVersion != null) {
              mergedSdkVersion = c.sdkVersion;
              break;
            }
          }
        }

        String? mergedRemark;
        for (final c in candidates) {
          if (c.remark != null && c.remark!.isNotEmpty) {
            mergedRemark = c.remark;
            break;
          }
        }
        mergedRemark ??= (_remarks[serial] ?? _remarks[best.id]);

        List<String> mergedTags = [];
        for (final c in candidates) {
          if (c.tags.isNotEmpty) {
            mergedTags = c.tags;
            break;
          }
        }
        if (mergedTags.isEmpty) {
          mergedTags = _tags[serial] ?? _tags[best.id] ?? [];
        }

        // When the merged device is online, we filter the connection IDs to only active (online) connections.
        // Otherwise, we show all historical offline connections.
        final connectionIds = best.isOnline
            ? candidates.where((c) => c.isOnline).map((c) => c.id).toList()
            : candidates.map((c) => c.id).toList();

        merged.add(
          best.copyWith(
            isChecked: anyChecked,
            customName: mergedCustomName,
            model: mergedModel,
            product: mergedProduct,
            connections: connectionIds,
            serial: serial,
            ipAddress: mergedIp,
            androidVersion: mergedAndroidVersion,
            sdkVersion: mergedSdkVersion,
            remark: mergedRemark,
            tags: mergedTags,
          ),
        );
      }
    });

    return merged;
  }

  /// 概览信息加载成功后触发同步更新设备注册表中的 Android 版本缓存并更新状态。
  void updateDeviceAndroidVersion(String id, String androidVersion) {
    if (androidVersion == '-' || androidVersion.isEmpty) return;

    final serial = _serialMap[id] ?? id;
    final currentVersion = _androidVersions[serial] ?? _androidVersions[id];
    final sdkVersion = _parseSdkVersion(androidVersion);
    final currentSdk = _sdkVersions[serial] ?? _sdkVersions[id];
    if (currentVersion == androidVersion &&
        (sdkVersion == null || currentSdk == sdkVersion)) {
      return;
    }

    _androidVersions[id] = androidVersion;
    if (sdkVersion != null) {
      _sdkVersions[id] = sdkVersion;
    }
    if (serial != id) {
      _androidVersions[serial] = androidVersion;
      if (sdkVersion != null) {
        _sdkVersions[serial] = sdkVersion;
      }
    }

    _saveAndroidVersions();

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 概览信息加载成功后触发同步更新设备注册表中的设备型号名称（供鸿蒙真实 marketing_name 回写）。
  void updateDeviceModel(String id, String modelName) {
    if (modelName.isEmpty || modelName == '-') return;
    // 通用占位名不回写，避免覆盖已有真实名称
    if (_isGenericHarmonyModel(modelName)) return;

    final current = _models[id];
    if (current == modelName) return;

    _models[id] = modelName;
    final serial = _serialMap[id] ?? id;
    if (serial != id) {
      _models[serial] = modelName;
    }

    _saveModelsAndProducts();

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  /// 概览信息加载成功后触发同步更新设备注册表中的 IP 缓存并更新状态
  void updateDeviceIp(String id, String ip) {
    if (ip == '-' || ip.isEmpty) return;

    final currentIp = _ipAddresses[id];
    if (currentIp == ip) return; // 无变化则不重复更新，避免 UI 抖动

    _ipAddresses[id] = ip;
    final serial = _serialMap[id] ?? id;
    if (serial != id) {
      _ipAddresses[serial] = ip;
    }

    _saveIps(); // 异步持久化到 SharedPreferences

    // 触发更新 state，让 UI 重新渲染
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<void> setAlias(String id, String alias) async {
    final serial = _serialMap[id] ?? id;
    final idsToAlias = _serialMap.entries
        .where((entry) => entry.value == serial)
        .map((entry) => entry.key)
        .toList();
    if (idsToAlias.isEmpty) {
      idsToAlias.add(id);
    }

    for (final aliasId in idsToAlias) {
      if (alias.trim().isEmpty) {
        _aliases.remove(aliasId);
      } else {
        _aliases[aliasId] = alias.trim();
      }
    }
    await _saveAliases();
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<void> updateRemark(String id, String remark) async {
    final targetIds = <String>{id};
    final serial = _serialMap[id] ?? id;
    targetIds.add(serial);
    for (final entry in _serialMap.entries) {
      if (entry.value == serial) {
        targetIds.add(entry.key);
      }
    }
    for (final dev in state) {
      if (dev.id == id || dev.serial == serial || dev.connections.contains(id)) {
        targetIds.add(dev.id);
        targetIds.addAll(dev.connections);
        if (dev.serial != null && dev.serial!.isNotEmpty) {
          targetIds.add(dev.serial!);
        }
      }
    }
    for (final targetId in targetIds) {
      if (remark.trim().isEmpty) {
        _remarks.remove(targetId);
      } else {
        _remarks[targetId] = remark.trim();
      }
    }
    await _saveRemarks();
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<void> updateTags(String id, List<String> tags) async {
    final targetIds = <String>{id};
    final serial = _serialMap[id] ?? id;
    targetIds.add(serial);
    for (final entry in _serialMap.entries) {
      if (entry.value == serial) {
        targetIds.add(entry.key);
      }
    }
    for (final dev in state) {
      if (dev.id == id || dev.serial == serial || dev.connections.contains(id)) {
        targetIds.add(dev.id);
        targetIds.addAll(dev.connections);
        if (dev.serial != null && dev.serial!.isNotEmpty) {
          targetIds.add(dev.serial!);
        }
      }
    }
    for (final targetId in targetIds) {
      if (tags.isEmpty) {
        _tags.remove(targetId);
      } else {
        _tags[targetId] = tags;
      }
    }
    await _saveTags();
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<void> _saveRemarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remarksKey, jsonEncode(_remarks));
  }

  Future<void> _saveTags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tagsKey, jsonEncode(_tags));
  }

  Future<void> removeDevice(String id) {
    return _removeDevices({id});
  }

  Future<void> removeCheckedDevices() {
    final checkedDeviceIds = state
        .where((device) => device.isChecked)
        .map((device) => device.id)
        .toSet();
    return _removeDevices(checkedDeviceIds);
  }

  Future<void> _removeDevices(Set<String> ids) async {
    if (ids.isEmpty) {
      return;
    }

    final idsToRemove = <String>{};
    for (final id in ids) {
      idsToRemove.add(id);
      for (final d in state) {
        if (d.id == id ||
            d.connections.contains(id) ||
            (d.serial != null && d.serial == id)) {
          idsToRemove.add(d.id);
          idsToRemove.addAll(d.connections);
          if (d.serial != null && d.serial!.isNotEmpty) {
            idsToRemove.add(d.serial!);
          }
        }
      }

      final serial = _serialMap[id] ?? id;
      final sameSerialIds = _serialMap.entries
          .where((entry) => entry.value == serial)
          .map((entry) => entry.key)
          .toSet();
      idsToRemove.addAll(sameSerialIds);
    }

    // 断开所有需要断开的网络连接（直接调用服务，避免 disconnectDevice 触发内部刷新从而重新载入未更新的旧持久化数据）
    final disconnectFutures = <Future<void>>[];
    for (final removeId in idsToRemove) {
      final isNetwork =
          removeId.contains(':') ||
          removeId.contains('.') ||
          removeId == '127.0.0.1';
      if (isNetwork) {
        disconnectFutures.add(
          ref
              .read(deviceActionServiceProvider)
              .disconnect(removeId)
              .then((_) {})
              .catchError((_) {}),
        );
      }
    }
    if (disconnectFutures.isNotEmpty) {
      await Future.wait(disconnectFutures);
    }

    for (final removeId in idsToRemove) {
      final selected = ref.read(selectedDeviceProvider);
      if (selected != null &&
          (selected.id == removeId || idsToRemove.contains(selected.id))) {
        ref.read(selectedDeviceProvider.notifier).clear();
      }

      _historyIds.remove(removeId);
      _checkedIds.remove(removeId);
      _aliases.remove(removeId);
      _models.remove(removeId);
      _products.remove(removeId);
      _ipAddresses.remove(removeId);
      _androidVersions.remove(removeId);
      _sdkVersions.remove(removeId);
      _serialMap.remove(removeId);
      _pendingFetchIds.remove(removeId);
      _attemptedFetchIds.remove(removeId);

      // 清除该设备的所有本地缓存信息 (包括概览缓存、包列表缓存、包图标缓存等)
      await ref.read(deviceInfoServiceProvider).clearDeviceCache(removeId);
      await ref.read(appManagementServiceProvider).clearDeviceCache(removeId);
    }

    await _saveHistory();
    await _saveAliases();
    await _saveModelsAndProducts();
    await _saveIps();
    await _saveAndroidVersions();

    var activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    activeDevices = activeDevices
        .where((d) => !idsToRemove.contains(d.id))
        .toList();
    _lastActiveDevices = activeDevices;
    state = _mergeDevices(activeDevices);
    ref.read(adbHeartbeatControllerProvider).trigger();
  }

  void toggleCheck(String id) {
    final serial = _serialMap[id] ?? id;
    final idsToToggle = _serialMap.entries
        .where((entry) => entry.value == serial)
        .map((entry) => entry.key)
        .toSet();
    idsToToggle.add(id);
    for (final d in state) {
      if (d.id == id ||
          d.connections.contains(id) ||
          d.serial == id ||
          (d.serial != null && d.serial == serial)) {
        idsToToggle.add(d.id);
        idsToToggle.addAll(d.connections);
      }
    }

    final isRepresentativeChecked = _checkedIds.contains(id) ||
        state
            .where((d) => d.id == id || d.connections.contains(id))
            .any((d) => d.isChecked);
    for (final toggleId in idsToToggle) {
      if (isRepresentativeChecked) {
        _checkedIds.remove(toggleId);
      } else {
        _checkedIds.add(toggleId);
      }
    }

    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  void toggleAll(bool checked) {
    if (checked) {
      final allRepresentedSerials = state
          .map((d) => _serialMap[d.id] ?? d.id)
          .toSet();
      _checkedIds = _serialMap.entries
          .where((entry) => allRepresentedSerials.contains(entry.value))
          .map((entry) => entry.key)
          .toSet();
      for (final d in state) {
        _checkedIds.add(d.id);
        _checkedIds.addAll(d.connections);
        if (d.serial != null && d.serial!.isNotEmpty) {
          _checkedIds.add(d.serial!);
        }
      }
    } else {
      _checkedIds.clear();
    }
    final activeDevices = ref.read(devicesProvider).value ?? _lastActiveDevices;
    state = _mergeDevices(activeDevices);
  }

  Future<AdbResult> connectDevice(String address) async {
    // 提取 IP 地址
    String ipAddress = address;
    if (address.contains(':')) {
      ipAddress = address.split(':').first;
    }

    // 1. 先判断方法一：是否在同一局域网网段
    final isSameSegment = await NetworkLanMatcher.isSameSubnet(ipAddress);
    if (!isSameSegment) {
      // 如果网段不同，进入方法二：尝试 Ping 测试
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：手机与电脑不在同一网段，且局域网 Ping 测试不通，请检查是否连接了相同的 WiFi。',
        );
      }
    }

    // 2. 优先执行 ADB 连接
    var result = await ref.read(deviceActionServiceProvider).connect(address);

    // 如果 ADB 连接失败，尝试作为鸿蒙设备通过 HDC 连接
    if (!result.isSuccess) {
      final hdcResult = await ref.read(hdcServiceProvider).connectWireless(address);
      if (hdcResult.isSuccess || hdcResult.stdout.contains('Connect OK')) {
        result = hdcResult;
      }
    }

    // 3. 如果点击连接发现不联通，再判断方法二（进行诊断）
    if (!result.isSuccess) {
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：虽然在同一网段，但局域网网络 Ping 测试不联通，请检查手机 WiFi 状态或 AP 隔离设置。',
        );
      } else {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：设备在局域网内网络连通，但手机调试端口未响应，请检查手机端是否允许调试。',
        );
      }
    }

    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  Future<AdbResult> disconnectDevice(String address) async {
    final isHarmony = state.any((d) => d.id == address && d.isHarmony) ||
        address.startsWith('harmony:');
    final AdbResult result;
    if (isHarmony) {
      result = await ref.read(hdcServiceProvider).disconnectWireless(address);
    } else {
      result = await ref
          .read(deviceActionServiceProvider)
          .disconnect(address);
    }
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  ///名字：connectWireless
  ///描述：通过Tcp/ip，无线连接设备
  ///实际执行命令：adb connect $ipAddress:$port 或 hdc tconn $ipAddress:$port
  Future<AdbResult> connectWireless(
    String usbDeviceId,
    String ipAddress, [
    int port = 5555,
  ]) async {
    // 1. 先判断方法一：是否在同一局域网网段
    final isSameSegment = await NetworkLanMatcher.isSameSubnet(ipAddress);
    if (!isSameSegment) {
      // 如果网段不同，进入方法二：尝试 Ping 测试
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：手机与电脑不在同一网段，且局域网 Ping 测试不通，请检查是否连接了相同的 WiFi。',
        );
      }
    }

    final isHarmony = state.any((d) => d.id == usbDeviceId && d.isHarmony);
    final AdbResult connectResult;

    if (isHarmony) {
      final hdc = ref.read(hdcServiceProvider);
      // 2. 将鸿蒙 USB 设备切换为 TCP 监听模式
      final tmodeResult = await hdc.enableTcpMode(usbDeviceId, port: port);
      if (!tmodeResult.isSuccess) {
        return tmodeResult;
      }

      // 3. 延迟等待 1 秒，以确保手机端的服务就绪
      await Future.delayed(const Duration(seconds: 1));

      // 4. 执行 hdc tconn 连接
      connectResult = await hdc.connectWireless('$ipAddress:$port');
    } else {
      final adb = ref.read(adbServiceProvider);

      // 2. 将 USB 设备切换为 TCP/IP 监听模式，开启指定端口（默认 5555）
      final tcpipResult = await adb.run([
        '-s',
        usbDeviceId,
        'tcpip',
        port.toString(),
      ]);
      if (!tcpipResult.isSuccess) {
        return tcpipResult;
      }

      // 3. 延迟等待 1 秒，以确保手机端的 TCP/IP 服务成功启动
      await Future.delayed(const Duration(seconds: 1));

      // 4. 执行 adb connect 连接到该局域网 IP
      connectResult = await adb.run(['connect', '$ipAddress:$port']);
    }

    // 5. 如果点击连接发现不联通，再判断方法二（进行诊断）
    if (!connectResult.isSuccess && !connectResult.stdout.contains('Connect OK')) {
      final isPingable = await NetworkLanMatcher.pingDevice(ipAddress);
      if (!isPingable) {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：虽然在同一网段，但局域网网络 Ping 测试不联通，请检查手机 WiFi 状态或 AP 隔离设置。',
        );
      } else {
        return const AdbResult(
          exitCode: 1,
          stdout: '',
          stderr: '连接失败：设备在局域网内网络连通，但手机无线端口未响应，请检查手机端是否允许调试或重新插拔 USB。',
        );
      }
    }

    await _refreshRegistryAfterAdbCommand();
    return connectResult;
  }

  /// 主动刷新设备列表，并立即同步到设备注册表。
  Future<AdbResult> refreshDevices() async {
    try {
      ref.read(adbHeartbeatControllerProvider).trigger();
      await _syncActiveDevices();
      return const AdbResult(
        exitCode: 0,
        stdout: 'Devices refreshed',
        stderr: '',
      );
    } on Object catch (error) {
      return AdbResult(exitCode: 1, stdout: '', stderr: error.toString());
    }
  }

  /// ADB 命令发现 transport 断开后，同步注册表与当前选中设备。
  Future<void> syncAfterAdbResult(AdbResult result) async {
    if (!result.isDeviceDisconnected) {
      return;
    }

    await refreshDevices();

    final disconnectedDeviceId = result.disconnectedDeviceId;
    final selected = ref.read(selectedDeviceProvider);
    if (selected == null || selected.id != disconnectedDeviceId) {
      return;
    }

    for (final device in state) {
      if (device.id == selected.id) {
        ref.read(selectedDeviceProvider.notifier).select(device.toAdbDevice);
        return;
      }
    }
  }

  /// 重启 ADB 服务并刷新设备列表。
  Future<AdbResult> restartAdb() async {
    final result = await ref.read(adbServiceProvider).restartServer();
    await _refreshRegistryAfterAdbCommand();
    return result;
  }

  Future<void> _refreshRegistryAfterAdbCommand() async {
    try {
      ref.read(adbHeartbeatControllerProvider).trigger();
      await _syncActiveDevices();
    } catch (_) {}
  }

  Future<void> _syncActiveDevices() async {
    _attemptedFetchIds.clear();
    final androidDevices = await ref.read(adbServiceProvider).listDevices();
    List<AdbDevice> iosDevices = [];
    try {
      iosDevices = await ref.read(iosDeviceServiceProvider).listDevices();
    } catch (_) {}
    List<AdbDevice> harmonyDevices = [];
    try {
      harmonyDevices = await ref.read(hdcServiceProvider).listDevices();
    } catch (_) {}
    final activeDevices = [...androidDevices, ...iosDevices, ...harmonyDevices];
    _lastActiveDevices = activeDevices;
    // 重新从持久化和概览缓存中加载最新的数据
    await _loadFromPrefs();
    state = _mergeDevices(activeDevices);
  }

  /// 使用配对码配对设备并自动发现端口连接。
  Future<AdbResult> pairAndConnect(
    String hostWithPort,
    String pairingCode,
  ) async {
    final adb = ref.read(adbServiceProvider);

    // 1. 执行配对
    final pairResult = await adb.run(['pair', hostWithPort, pairingCode]);
    if (!pairResult.isSuccess) {
      return pairResult;
    }

    // 2. 配对成功后，尝试自动发现连接端口并连接
    final ip = hostWithPort.split(':').first;

    // 轮询 5 次尝试发现 _adb-tls-connect 服务
    String? connectAddress;
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      final servicesResult = await adb.run(['mdns', 'services']);
      if (servicesResult.isSuccess) {
        final lines = servicesResult.stdout.split('\n');
        for (final line in lines) {
          if (line.contains('_adb-tls-connect._tcp') && line.contains(ip)) {
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              connectAddress = parts[2].trim();
              break;
            }
          }
        }
      }
      if (connectAddress != null) {
        break;
      }
    }

    // 3. 执行连接
    final addressToConnect = connectAddress ?? '$ip:5555';
    final connectResult = await connectDevice(addressToConnect);

    return AdbResult(
      exitCode: connectResult.exitCode,
      stdout:
          'Successfully paired to $hostWithPort. Connection result: ${connectResult.message}',
      stderr: connectResult.stderr,
    );
  }
}

/// 终端调试会话列表（按设备划分）
final adbTerminalProvider =
    NotifierProvider<AdbTerminalNotifier, AdbTerminalState>(
      AdbTerminalNotifier.new,
    );

/// 收藏调试命令
final favoriteCommandsProvider =
    NotifierProvider<FavoriteCommandsNotifier, List<FavoriteCommand>>(
      FavoriteCommandsNotifier.new,
    );

/// 模拟器底层服务实例。
final emulatorServiceProvider = Provider<EmulatorService>((ref) {
  return EmulatorService(
    hostPlatformService: ref.watch(hostPlatformServiceProvider),
  );
});

/// 可用 AVD 模拟器配置列表。
final emulatorListProvider = FutureProvider.autoDispose<List<AndroidEmulator>>((
  ref,
) async {
  return ref.watch(emulatorServiceProvider).listEmulators();
});

/// 正在启动的模拟器集合状态。
class StartingEmulatorsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {};

  void start(String name) {
    state = {...state, name};
  }

  void stopStarting(String name) {
    state = state.where((n) => n != name).toSet();
  }

  void setStarting(Set<String> next) {
    state = next;
  }
}

final startingEmulatorsProvider =
    NotifierProvider<StartingEmulatorsNotifier, Set<String>>(
      StartingEmulatorsNotifier.new,
    );

/// 当前正在运行的模拟器，以 map 形式提供：AVD名称 -> 对应的设备ID。
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

// Track whether the physical screen is turned off for each device.
// Defaults to false (screen is on).
class ScreenPowerOffNotifier extends Notifier<bool> {
  ScreenPowerOffNotifier(this.deviceId);
  final String deviceId;
  Process? _geteventProcess;
  Timer? _secureCheckTimer;
  int? _savedBrightness;
  int? _savedBrightnessMode;

  @override
  bool build() {
    ref.onDispose(() {
      _stopListener();
      _secureCheckTimer?.cancel();
    });
    return false;
  }

  // 供外部与内部统一调用的亮灭控制接口，实现状态与物理控制收口
  Future<void> toggleScreenPower(bool off) async {
    if (state == off) return;
    
    final isHarmony = ref
        .read(deviceRegistryProvider)
        .any((device) => device.id == deviceId && device.isHarmony);
    if (isHarmony) {
      final result = await ref
          .read(hdcServiceProvider)
          .setScreenPower(deviceId, powerOn: !off);
      if (result.isSuccess) {
        state = off;
      }
      return;
    }

    final adb = ref.read(adbServiceProvider);

    if (off) {
      // 息屏前：保存当前的亮度和自动亮度模式，以便亮屏时可以完美恢复，解决荣耀等机型息屏后亮度变最低的假死现象
      try {
        final brightnessRes = await adb.shell(deviceId, "settings get system screen_brightness");
        if (brightnessRes.isSuccess) {
          _savedBrightness = int.tryParse(brightnessRes.stdout.trim());
        }
        final modeRes = await adb.shell(deviceId, "settings get system screen_brightness_mode");
        if (modeRes.isSuccess) {
          _savedBrightnessMode = int.tryParse(modeRes.stdout.trim());
        }
      } catch (e) {
        stdout.writeln('[ScreenPowerOff] Failed to save brightness settings: $e');
      }
    }

    // 改变物理手机显示器供电状态
    await _setScreenPowerMode(!off);
    
    if (!off) {
      // 亮屏后：将原本被物理手机系统暗置为最低的亮度重新唤醒。由于部分手机在自动亮度模式下会忽略亮度修改命令，我们必须先切到手动模式(0)，设置亮度，再切回自动模式。
      try {
        // 1. 强制将亮度模式设为手动 (0)
        await adb.shellArgs(deviceId, ['settings', 'put', 'system', 'screen_brightness_mode', '0']);
        
        // 2. 写入原亮度或高对比度兜底值 (150)
        final targetBrightness = _savedBrightness ?? 150;
        await adb.shellArgs(deviceId, ['settings', 'put', 'system', 'screen_brightness', targetBrightness.toString()]);
        
        // 3. 如果用户原先开启了自动亮度，在 200 毫秒后恢复自动亮度模式 (1)
        if (_savedBrightnessMode == 1) {
          Future.delayed(const Duration(milliseconds: 200), () async {
            await adb.shellArgs(deviceId, ['settings', 'put', 'system', 'screen_brightness_mode', '1']);
          });
        }
      } catch (e) {
        stdout.writeln('[ScreenPowerOff] Failed to restore brightness settings: $e');
      }
    }

    state = off;
    if (off) {
      _startListener();
      _startSecureCheck();
    } else {
      _stopListener();
      _stopSecureCheck();
    }
  }

  // 传统的 setOff 仅做逻辑状态迁移与监听切换
  void setOff(bool value) {
    if (state == value) return;
    state = value;
    if (value) {
      _startListener();
      _startSecureCheck();
    } else {
      _stopListener();
      _stopSecureCheck();
    }
  }

  // 启动安全界面防双黑屏监控（周期轮询）
  void _startSecureCheck() {
    _secureCheckTimer?.cancel();
    final adb = ref.read(adbServiceProvider);
    _secureCheckTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      try {
        // 利用 shell 管道匹配当前焦点窗口属性是否拥有安全屏障（FLAG_SECURE）或是系统锁屏界面
        final res = await adb.shell(
          deviceId,
          "dumpsys window windows | grep -A 15 'mCurrentFocus' | grep -E 'FLAG_SECURE|password|credential|pin|lock'",
        );
        if (res.isSuccess && res.stdout.trim().isNotEmpty) {
          stdout.writeln('[ScreenPowerOff] FLAG_SECURE window or lock screen detected! Force waking screen to allow input.');
          // 一旦监测到黑屏安全壁垒，强制退出息屏，瞬间点亮物理手机供用户交互
          await toggleScreenPower(false);
        }
      } catch (e) {
        stdout.writeln('[ScreenPowerOff] Secure check error: $e');
      }
    });
  }

  // 关闭安全界面监控
  void _stopSecureCheck() {
    _secureCheckTimer?.cancel();
    _secureCheckTimer = null;
  }

  // 开启物理手机触摸/按键监听器
  void _startListener() async {
    _stopListener();
    final adb = ref.read(adbServiceProvider);
    final startTime = DateTime.now(); // 记录监听器启动的初始时间
    try {
      stdout.writeln('[ScreenPowerOff] starting getevent listener for $deviceId');
      // 启动 adb shell getevent 持续监听手机硬件的输入事件
      _geteventProcess = await Process.start(
        adb.executable,
        ['-s', deviceId, 'shell', 'getevent'],
      );

      // 用正则匹配格式为 /dev/input/eventX: 的真实硬件输入事件，用以过滤设备列表等初始化信息
      final eventRegex = RegExp(r'/dev/input/event\d+:');

      _geteventProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) async {
        stdout.writeln('[ScreenPowerOff] getevent stdout: $line');
        if (eventRegex.hasMatch(line)) {
          // 过滤息屏瞬间 1 秒内的噪点/系统状态余震事件，防止误判导致瞬间重新唤醒
          final elapsed = DateTime.now().difference(startTime);
          if (elapsed.inMilliseconds < 1000) {
            stdout.writeln('[ScreenPowerOff] Ignored early event (cooldown): $line');
            return;
          }
          stdout.writeln('[ScreenPowerOff] touch event detected! stopping listener and waking screen.');
          // 检测到触摸或硬件按键，直接调用统一接口退出息屏
          await toggleScreenPower(false);
        }
      });

      // 监听错误日志流
      _geteventProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stdout.writeln('[ScreenPowerOff] getevent stderr: $line');
      });

      // 监听进程退出状态
      _geteventProcess!.exitCode.then((code) {
        stdout.writeln('[ScreenPowerOff] getevent exited with code: $code');
        _geteventProcess = null;
      });
    } catch (e) {
      stdout.writeln('Failed to start getevent listener: $e');
    }
  }

  // 关闭并注销物理手机的触摸/按键监听器，杀掉后台 adb 进程
  void _stopListener() {
    _geteventProcess?.kill();
    _geteventProcess = null;
  }

  // 向 scrcpy 发送控制模式命令 (10 代表设置屏幕电源模式，2 代表亮屏，0 代表息屏)
  Future<bool> _setScreenPowerMode(bool powerOn) async {
    final buffer = ByteData(2);
    buffer.setUint8(0, 10); // 控制消息类型：设置屏幕电源模式
    buffer.setUint8(1, powerOn ? 2 : 0); // 2 = 正常亮屏, 0 = 息屏
    final message = buffer.buffer.asUint8List();
    bool success = false;
    try {
      success = await ref.read(embeddedScrcpyServiceProvider).sendControl(
        deviceId: deviceId,
        controlMessage: message,
      );
    } catch (_) {}
    if (powerOn) {
      // 荣耀/华为等设备兼容性双重保障：
      final adb = ref.read(adbServiceProvider);
      // 保障一：向 Android 系统注入 KEYCODE_WAKEUP (224) 唤醒键以点亮背光
      await adb.shellArgs(deviceId, ['input', 'keyevent', '224']);
      // 保障二：向屏幕注入一次微小的滑动事件 (swipe 10 10 10 10)，迫使系统的 PowerManager 触发 userActivity 物理激活屏幕
      await adb.shellArgs(deviceId, ['input', 'swipe', '10', '10', '10', '10']);
      return true;
    }
    return success;
  }
}

final screenPowerOffProvider =
    NotifierProvider.family<ScreenPowerOffNotifier, bool, String>(
      ScreenPowerOffNotifier.new,
    );
