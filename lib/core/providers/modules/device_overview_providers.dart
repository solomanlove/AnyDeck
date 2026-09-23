import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../device_info/device_memory_info.dart';
import '../../device_info/device_overview.dart';
import '../../harmony/hdc_service.dart';
import 'device_registry_providers.dart';
import 'device_tracking_providers.dart';
import 'registered_device_model.dart';
import 'service_providers.dart';

/// 单台设备的硬件与系统信息概览 StreamProvider。
///
/// 家族入参 [deviceId] 为设备 ID。
/// 支持零延迟本地缓存秒开；对于在线设备通过 HDC / ADB / iOS 探针异步获取详细的处理器、存储、内存、分辨率与网络参数。
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

            bool isValid(String s) => !HdcServiceDeviceInfo.isGenericOrInvalidModel(s);

            if (isValid(marketingName)) {
              name = marketingName;
            } else if (isValid(devName)) {
              name = devName;
            }
            if (isValid(devBrand)) brand = devBrand;
            if (isValid(devModel)) model = devModel;

            final verSuffix = (isValid(devSoft)) ? ' ($devSoft)' : '';
            if (isValid(fullname)) {
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

/// 单台设备是否拥有 Root 权限 Provider（支持 adb shell 已提权或通过 su 提权）。
///
/// 入参 [deviceId] 为目标设备 ID。
final isDeviceRootProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  deviceId,
) async {
  final status = await ref.watch(deviceRootStatusProvider(deviceId).future);
  return status == true;
});

/// 检查手机是否能通过 su 获取 root Provider；检测失败或授权被拒绝时不猜测结果，返回 null。
///
/// 入参 [deviceId] 为目标设备 ID。
final deviceRootStatusProvider = FutureProvider.autoDispose.family<bool?, String>((
  ref,
  deviceId,
) async {
  if (!ref.watch(deviceOnlineProvider(deviceId))) return null;

  final adb = ref.watch(adbServiceProvider);
  try {
    final shellIdentity = await adb.shell(deviceId, 'id');
    if (!shellIdentity.isSuccess) return null;
    if (shellIdentity.stdout.contains('uid=0(')) return true;

    final suPath = await adb.shell(deviceId, 'command -v su');
    if (suPath.exitCode == 1 && suPath.stdout.trim().isEmpty) return false;
    if (!suPath.isSuccess || suPath.stdout.trim().isEmpty) return null;

    final suIdentity = await adb.shell(
      deviceId,
      'su -c id',
      timeout: const Duration(seconds: 5),
    );
    return suIdentity.isSuccess && suIdentity.stdout.contains('uid=0(')
        ? true
        : null;
  } catch (_) {
    return null;
  }
});

/// 离线设备的本地手机信息概览缓存读取 Provider。
///
/// 入参 [deviceId] 为目标设备 ID。
final cachedDeviceOverviewProvider = FutureProvider.autoDispose
    .family<DeviceOverview?, String>((ref, deviceId) {
      return ref.watch(deviceInfoServiceProvider).loadFromCache(deviceId);
    });
