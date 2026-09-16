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
  });

  final AppManagementService service;
  final String deviceId;
  final String? canonicalId;
  final List<String> fallbackKeys;
  final bool Function() isActive;
  final void Function(List<AdbPackage>) publishPackages;
  final bool isHarmony;

  Future<void> run({PackageRefreshCallback? onProgress}) async {
    var progress = const PackageRefreshProgress();
    void report(PackageRefreshProgress next) {
      progress = next;
      if (isActive()) onProgress?.call(next);
    }

    try {
      report(progress);
      await service.clearPackageCache(
        deviceId,
        canonicalId: canonicalId,
        fallbackKeys: fallbackKeys,
      );
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
      report(
        PackageRefreshProgress(
          stage: PackageRefreshStage.enriching,
          total: packages.length,
        ),
      );
      if (packages.isNotEmpty) {
        await for (final updated in service.enrichPackagesWithIconsProgressive(
          deviceId,
          packages,
          onProgress: report,
          throwOnError: true,
          isActive: isActive,
          isHarmony: isHarmony,
          canonicalId: canonicalId,
          fallbackKeys: fallbackKeys,
        )) {
          if (!isActive()) return;
          packages = updated;
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
