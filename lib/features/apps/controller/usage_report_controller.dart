import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/usage/usage_snapshot.dart';
import '../../../core/usage/usage_sync_service.dart';
import '../../../core/usage/companion_database.dart';

/// 可注入临时 SQLite 文件，用真实持久化接口验证事务与恢复。
final companionDatabaseProvider = FutureProvider<CompanionDatabase>(
  (ref) => CompanionDatabase.openDefault(),
);

/// 设备级同步状态；页面关闭后释放，不启动自动轮询或图标查询。
final usageReportProvider = NotifierProvider.autoDispose
    .family<UsageReportController, UsageReportState, String>(
      UsageReportController.new,
    );

class UsageReportState {
  const UsageReportState({
    this.snapshot,
    this.busy = false,
    this.messageKey,
    this.failed = false,
    this.history = const CompanionHistoryView(),
  });
  final UsageSnapshot? snapshot;
  final bool busy;
  final String? messageKey;
  final bool failed;
  final CompanionHistoryView history;
}

/// 控制缓存读取、安装、打开授权页与手动同步，异步结束前检查生命周期。
class UsageReportController extends Notifier<UsageReportState> {
  UsageReportController(this.deviceId);
  final String deviceId;
  final _cache = UsageSnapshotCache();
  int _revision = 0;
  Future<void>? _loading;

  String get _route {
    for (final device in ref.read(deviceRegistryProvider)) {
      if (device.id == deviceId ||
          device.serial == deviceId ||
          device.connections.contains(deviceId)) {
        return device.serial ?? deviceId;
      }
    }
    return deviceId;
  }

  UsageSyncService get _service => UsageSyncService(
    ref.read(adbServiceProvider),
    ref.read(appManagementServiceProvider),
  );

  @override
  UsageReportState build() {
    _loading = _load();
    return const UsageReportState();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final database = await ref.read(companionDatabaseProvider.future);
      if (!ref.mounted || revision != _revision) return;
      final route = _route;
      var history = await database.load(route);
      if (history.source == null) {
        final legacy = await _cache.load(deviceId);
        if (legacy != null) {
          await database.migrateLegacy(route, legacy);
          history = await database.load(route);
        }
      }
      if (ref.mounted && revision == _revision) {
        state = UsageReportState(
          snapshot: history.usage.firstOrNull,
          history: history,
        );
      }
    } catch (_) {
      if (ref.mounted && revision == _revision) {
        state = const UsageReportState(
          messageKey: 'usageSaveFailed',
          failed: true,
        );
      }
    }
  }

  Future<void> sync() => _syncHistory('usage');
  Future<void> syncLocations() => _syncHistory('location');

  Future<void> _syncHistory(String kind) => _run(() async {
    final route = _route;
    final database = await ref.read(companionDatabaseProvider.future);
    if (!ref.mounted) return;
    try {
      await _service.syncHistory(
        deviceId,
        route,
        kind,
        database,
        isActive: () => ref.mounted,
      );
    } finally {
      // 中途失败仍显示已经事务提交的页；下一次从数据库游标恢复。
      final history = await database.load(route);
      if (ref.mounted) {
        state = UsageReportState(
          snapshot: history.usage.firstOrNull,
          history: history,
          busy: true,
        );
      }
    }
  }, 'usageSyncDone');

  void selectSnapshot(UsageSnapshot snapshot) {
    if (state.busy) return;
    state = UsageReportState(snapshot: snapshot, history: state.history);
  }

  Future<void> install() =>
      _run(() => _service.install(deviceId), 'usageSetupHint');

  Future<void> open() =>
      _run(() => _service.openCompanion(deviceId), 'usageSetupHint');

  Future<void> clear() => _run(() async {
    final route = _route;
    final database = await ref.read(companionDatabaseProvider.future);
    await database.clear(route);
    await _cache.clear(deviceId);
    if (ref.mounted) state = const UsageReportState(busy: true);
  }, 'usageCacheCleared');

  Future<void> _run(Future<void> Function() task, String successKey) async {
    if (state.busy) return;
    _revision++;
    state = UsageReportState(
      snapshot: state.snapshot,
      history: state.history,
      busy: true,
    );
    try {
      // 等待初次迁移结束，避免清除历史后尚未完成的迁移又写回旧数据。
      await _loading;
      if (!ref.mounted) return;
      await task();
      if (ref.mounted) {
        state = UsageReportState(
          snapshot: state.snapshot,
          history: state.history,
          messageKey: successKey,
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = UsageReportState(
          snapshot: state.snapshot,
          history: state.history,
          failed: true,
          messageKey: error is UsageSyncException
              ? error.messageKey
              : 'usageReadFailed',
        );
      }
    }
  }
}
