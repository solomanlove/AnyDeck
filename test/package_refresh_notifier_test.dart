import 'dart:async';

import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/apps/package_refresh_progress.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';

/// 使用可控 Future 验证 Provider 的阶段顺序、重入和释放边界。
class _RefreshService extends AppManagementService {
  _RefreshService() : super(FakeAdbService());
  List<AdbPackage> packages = [const AdbPackage(name: 'new.app')];
  Future<List<AdbPackage>?>? cached;
  Completer<void>? readGate;
  Completer<void>? saveGate;
  bool failRead = false;
  bool failSave = false;
  int failed = 0;
  int reads = 0;
  int saves = 0;

  @override
  Future<List<AdbPackage>?> loadPackageCache(String deviceId) async =>
      await (cached ?? Future.value([const AdbPackage(name: 'old.app')]));

  @override
  Future<void> clearPackageCache(String deviceId) async {}

  @override
  Future<List<AdbPackage>> refreshPackages(
    String deviceId, {
    bool refreshIconsInBackground = true,
  }) async {
    expect(refreshIconsInBackground, isFalse);
    reads++;
    if (readGate != null) await readGate!.future;
    if (failRead) throw StateError('read failed');
    return packages;
  }

  @override
  Stream<List<AdbPackage>> enrichPackagesWithIconsProgressive(
    String deviceId,
    List<AdbPackage> packages, {
    PackageRefreshCallback? onProgress,
    bool throwOnError = false,
    bool Function()? isActive,
  }) async* {
    expect(throwOnError, isTrue);
    onProgress?.call(
      PackageRefreshProgress(
        stage: PackageRefreshStage.enriching,
        processed: packages.length,
        total: packages.length,
        failed: failed,
      ),
    );
    yield packages;
  }

  @override
  Future<void> savePackageCache(
    String deviceId,
    List<AdbPackage> packages,
  ) async {
    saves++;
    if (saveGate != null) await saveGate!.future;
    if (failSave) throw StateError('save failed');
  }
}

void main() {
  late _RefreshService service;
  late ProviderContainer container;
  late PackagesNotifier notifier;
  setUp(() async {
    service = _RefreshService();
    container = ProviderContainer(
      overrides: [appManagementServiceProvider.overrideWithValue(service)],
    );
    notifier = container.read(packagesProvider('device').notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() => container.dispose());

  test('读取到保存的阶段完整，保存完成前不发送成功状态，重复点击复用任务', () async {
    service.readGate = Completer<void>();
    service.saveGate = Completer<void>();
    final progress = <PackageRefreshProgress>[];
    final task = notifier.refreshAllPackagesWithIcons(onProgress: progress.add);
    expect(progress.single.stage, PackageRefreshStage.reading);
    expect(progress.single.fraction, isNull);
    expect(identical(task, notifier.refreshAllPackagesWithIcons()), isTrue);
    service.readGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(progress.last.stage, PackageRefreshStage.saving);
    expect(progress.last.fraction, isNull);
    expect(service.reads, 1);
    service.saveGate!.complete();
    await task;
    expect(progress.last.stage, PackageRefreshStage.completed);
    expect(progress.last.processed, 1);
    expect(
      container.read(packagesProvider('device')).value!.single.name,
      'new.app',
    );
  });

  test('空列表完成缓存保存且没有除零', () async {
    service.packages = [];
    final progress = <PackageRefreshProgress>[];
    await notifier.refreshAllPackagesWithIcons(onProgress: progress.add);
    expect(progress.last.total, 0);
    expect(progress.last.fraction, 1);
    expect(service.saves, 1);
  });

  test('部分失败数量保留到最终结果', () async {
    service.failed = 1;
    final progress = <PackageRefreshProgress>[];
    await notifier.refreshAllPackagesWithIcons(onProgress: progress.add);
    expect(progress.last.stage, PackageRefreshStage.completed);
    expect(progress.last.failed, 1);
    expect(service.saves, 1);
  });

  for (final saving in [false, true]) {
    test('${saving ? '保存' : '读取'} 异常暴露失败阶段并允许再次刷新', () async {
      service.failRead = !saving;
      service.failSave = saving;
      final progress = <PackageRefreshProgress>[];
      await expectLater(
        notifier.refreshAllPackagesWithIcons(onProgress: progress.add),
        throwsStateError,
      );
      expect(progress.last.stage, PackageRefreshStage.failed);
      expect(
        progress.last.error,
        contains(saving ? 'save failed' : 'read failed'),
      );
      service.failRead = false;
      service.failSave = false;
      await notifier.refreshAllPackagesWithIcons(onProgress: progress.add);
      expect(progress.last.stage, PackageRefreshStage.completed);
    });
  }

  test('Provider 释放后不继续保存或发布进度', () async {
    service.readGate = Completer<void>();
    final progress = <PackageRefreshProgress>[];
    final task = notifier.refreshAllPackagesWithIcons(onProgress: progress.add);
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    service.readGate!.complete();
    await task;
    expect(service.saves, 0);
    expect(progress, hasLength(1));
    // tearDown 仍有一个有效容器可以释放。
    container = ProviderContainer();
  });

  test('较晚返回的首次缓存加载不会覆盖手动刷新结果', () async {
    final cached = Completer<List<AdbPackage>?>();
    service.cached = cached.future;
    final other = container.read(packagesProvider('other').notifier);
    await other.refreshAllPackagesWithIcons();
    cached.complete([const AdbPackage(name: 'stale.app')]);
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(packagesProvider('other')).value!.single.name,
      'new.app',
    );
  });
}
