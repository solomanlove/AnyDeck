import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../apps/adb_package.dart';
import '../../apps/app_management_service.dart';
import '../../apps/package_refresh_progress.dart';
import '../../apps/package_refresh_runner.dart';
import 'device_registry_providers.dart';
import 'device_tracking_providers.dart';
import 'registered_device_model.dart';
import 'service_providers.dart';

/// 单台设备的已安装应用列表 Provider。
///
/// 家族参数 [deviceId] 为设备 ID。
/// 内部采用“内存秒开 -> 磁盘持久化缓存 -> 后台差异异步获取”的三级加载机制。
final packagesProvider = NotifierProvider.autoDispose
    .family<PackagesNotifier, AsyncValue<List<AdbPackage>>, String>(
      PackagesNotifier.new,
    );

/// 应用包列表控制器，管理单台设备的应用加载、全量图标分批刷新与单包增量同步。
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
        if (_isHarmony && ref.read(deviceOnlineProvider(deviceId))) {
          unawaited(_loadHarmonySummaries(cached, revision));
        }
        return;
      }

      // 如果已有初始内存数据（由同一设备上一通道继承），且本地无新数据，保留现状不打断用户
      if (hasInitialData && state.hasValue) {
        if (_isHarmony && ref.read(deviceOnlineProvider(deviceId))) {
          unawaited(_loadHarmonySummaries(state.value!, revision));
        }
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
      if (_isHarmony) {
        unawaited(_loadHarmonySummaries(initialPackages, revision));
      }
    } catch (err, stack) {
      // 若当前已有数据，网络或瞬态异常时不冲掉已有数据
      if (!isDisposed && revision == _loadRevision && !state.hasValue) {
        state = AsyncValue.error(err, stack);
      }
    }
  }

  /// 鸿蒙批量列表仅含名称；限制并发逐包读取详情并分批更新可见列表。
  Future<void> _loadHarmonySummaries(
    List<AdbPackage> packages,
    int revision, {
    bool force = false,
  }) async {
    final targets = packages.where((package) =>
        force ||
        package.versionLabel == '-' ||
        package.firstInstallTime == null ||
        (package.storageBytes == null && !package.storagePermissionDenied),
    ).toList(growable: false);
    if (targets.isEmpty) return;
    final service = ref.read(appManagementServiceProvider);
    const batchSize = 4;
    for (var start = 0; start < targets.length; start += batchSize) {
      if (!ref.mounted || revision != _loadRevision) return;
      final batch = targets.skip(start).take(batchSize);
      final updates = await Future.wait(batch.map((package) async {
        try {
          return await service.getHarmonyPackageSummary(deviceId, package);
        } catch (_) {
          return null;
        }
      }));
      if (!ref.mounted || revision != _loadRevision) return;
      final byName = <String, AdbPackage>{};
      for (final update in updates) {
        if (update != null) byName[update.name] = update;
      }
      if (byName.isEmpty) continue;
      final current = state.value;
      if (current == null) return;
      state = AsyncValue.data([
        for (final package in current)
          if (byName[package.name] case final update?)
            package.copyWith(
              versionName: update.versionName,
              versionCode: update.versionCode,
              targetSdk: update.targetSdk,
              firstInstallTime: update.firstInstallTime,
              storageBytes: update.storageBytes,
              storagePermissionDenied: update.storagePermissionDenied,
            )
          else
            package,
      ]);
    }
    if (!ref.mounted || revision != _loadRevision) return;
    await service.savePackageCache(
      deviceId,
      state.value!,
      canonicalId: _canonicalId,
      fallbackKeys: _fallbackKeys,
    );
  }

  /// 手动刷新全部或指定类型应用时，重新读取元数据并分批加载应用图标。
  Future<void> refreshAllPackagesWithIcons({
    PackageRefreshCallback? onProgress,
    bool Function(AdbPackage)? filter,
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
      filter: filter,
    );
    return _refreshAllTask = runner.run(onProgress: onProgress).then((_) {
      if (ref.mounted && _isHarmony && state.hasValue) {
        unawaited(_loadHarmonySummaries(state.value!, _loadRevision, force: true));
      }
    }).whenComplete(() {
      _refreshAllTask = null;
    });
  }

  /// 刷新单个应用的最新状态，并更新 state 与本地缓存。
  Future<void> refreshSinglePackage(String packageName) async {
    final current = state.value;
    if (current == null) return;

    final service = ref.read(appManagementServiceProvider);
    var updated = await service.getSinglePackageInfo(
      deviceId,
      packageName,
      isHarmony: _isHarmony,
    );
    if (_isHarmony && updated != null) {
      updated = await service.getHarmonyPackageSummary(deviceId, updated) ?? updated;
    }

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
          versionName: updated.versionName ?? old.versionName,
          versionCode: updated.versionCode ?? old.versionCode,
          targetSdk: updated.targetSdk ?? old.targetSdk,
          storageBytes: updated.storageBytes ?? old.storageBytes,
          storagePermissionDenied: updated.storagePermissionDenied,
          firstInstallTime: updated.firstInstallTime ?? old.firstInstallTime,
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

  /// 批量从列表中移除指定的包名，并立即同步更新内存状态与本地磁盘持久化缓存（无需重新请求设备）。
  Future<void> removePackages(Set<String> packageNames) async {
    if (packageNames.isEmpty) return;
    final current = state.value;
    if (current == null) return;

    final newList = current
        .where((p) => !packageNames.contains(p.name))
        .toList(growable: false);

    state = AsyncValue.data(newList);

    final service = ref.read(appManagementServiceProvider);
    await service.savePackageCache(
      deviceId,
      newList,
      canonicalId: _canonicalId,
      fallbackKeys: _fallbackKeys,
    );
  }
}

/// 全局包展示元数据解析服务 Provider。
final packageMetadataResolverProvider = Provider<PackageMetadataResolver>((ref) {
  final service = ref.watch(appManagementServiceProvider);
  final resolver = PackageMetadataResolver(
    service,
    onCacheUpdated: () {
      try {
        ref.read(packageMetadataRevisionProvider.notifier).increment();
      } catch (_) {}
    },
  );
  resolver.warmup();
  return resolver;
});

/// 包元数据全局版本号 Notifier，当有新的名称或图标加载完成时递增，触发监听它的 UI 组件刷新。
final packageMetadataRevisionProvider =
    NotifierProvider<PackageMetadataRevisionNotifier, int>(
      PackageMetadataRevisionNotifier.new,
    );

class PackageMetadataRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() {
    state++;
  }
}

