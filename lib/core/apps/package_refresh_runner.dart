import 'adb_package.dart';
import 'app_management_service.dart';
import 'package_refresh_progress.dart';

/// 编排刷新、批次回写和最终缓存落盘；Provider 释放后停止发布状态。
class PackageRefreshRunner {
  const PackageRefreshRunner({
    required this.service,
    required this.deviceId,
    required this.isActive,
    required this.publishPackages,
    this.canonicalId,
    this.fallbackKeys = const [],
    this.isHarmony = false,
    this.filter,
  });

  final AppManagementService service;
  final String deviceId;
  final String? canonicalId;
  final List<String> fallbackKeys;
  final bool Function() isActive;
  final void Function(List<AdbPackage>) publishPackages;
  final bool isHarmony;
  final bool Function(AdbPackage)? filter;

  Future<void> run({PackageRefreshCallback? onProgress}) async {
    var progress = const PackageRefreshProgress();
    void report(PackageRefreshProgress next) {
      progress = next;
      if (isActive()) onProgress?.call(next);
    }

    try {
      report(progress);
      if (filter == null) {
        await service.clearPackageCache(
          deviceId,
          canonicalId: canonicalId,
          fallbackKeys: fallbackKeys,
        );
      }
      if (!isActive()) return;
      var packages = await service.refreshPackages(
        deviceId,
        refreshIconsInBackground: false,
        canonicalId: canonicalId,
        fallbackKeys: fallbackKeys,
        isHarmony: isHarmony,
      );
      if (!isActive()) return;
      publishPackages(packages);

      final targetPackages = filter == null
          ? packages
          : packages.where(filter!).toList(growable: false);

      report(
        PackageRefreshProgress(
          stage: PackageRefreshStage.enriching,
          total: targetPackages.length,
        ),
      );
      if (targetPackages.isNotEmpty) {
        await for (final updated in service.enrichPackagesWithIconsProgressive(
          deviceId,
          targetPackages,
          onProgress: report,
          throwOnError: true,
          isActive: isActive,
          isHarmony: isHarmony,
          canonicalId: canonicalId,
          fallbackKeys: fallbackKeys,
        )) {
          if (!isActive()) return;
          if (filter == null) {
            packages = updated;
          } else {
            final updatedMap = {for (final p in updated) p.name: p};
            packages = packages
                .map((p) => updatedMap[p.name] ?? p)
                .toList(growable: false);
          }
          publishPackages(packages);
        }
      }
      if (!isActive()) return;
      report(progress.atStage(PackageRefreshStage.saving));
      await service.savePackageCache(
        deviceId,
        packages,
        canonicalId: canonicalId,
        fallbackKeys: fallbackKeys,
      );
      if (!isActive()) return;
      report(progress.atStage(PackageRefreshStage.completed));
    } catch (error) {
      report(
        progress.atStage(PackageRefreshStage.failed, error: error.toString()),
      );
      rethrow;
    }
  }
}
