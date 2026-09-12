import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/usage/usage_snapshot.dart';
import '../../../core/usage/usage_sync_service.dart';

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
  });
  final UsageSnapshot? snapshot;
  final bool busy;
  final String? messageKey;
  final bool failed;
}

/// 控制缓存读取、安装、打开授权页与手动同步，异步结束前检查生命周期。
class UsageReportController extends Notifier<UsageReportState> {
  UsageReportController(this.deviceId);
  final String deviceId;
  final _cache = UsageSnapshotCache();
  int _revision = 0;

  UsageSyncService get _service => UsageSyncService(
    ref.read(adbServiceProvider),
    ref.read(appManagementServiceProvider),
  );

  @override
  UsageReportState build() {
    _load();
    return const UsageReportState();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final snapshot = await _cache.load(deviceId);
      if (ref.mounted && revision == _revision) {
        state = UsageReportState(snapshot: snapshot);
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

  Future<void> sync() => _run(() async {
    final snapshot = await _service.sync(deviceId);
    if (!ref.mounted) return;
    await _cache.save(deviceId, snapshot);
    if (ref.mounted) state = UsageReportState(snapshot: snapshot, busy: true);
  }, 'usageSyncDone');

  Future<void> install() =>
      _run(() => _service.install(deviceId), 'usageSetupHint');

  Future<void> open() =>
      _run(() => _service.openCompanion(deviceId), 'usageSetupHint');

  Future<void> clear() => _run(() async {
    await _cache.clear(deviceId);
    if (ref.mounted) state = const UsageReportState(busy: true);
  }, 'usageCacheCleared');

  Future<void> _run(Future<void> Function() task, String successKey) async {
    if (state.busy) return;
    _revision++;
    state = UsageReportState(snapshot: state.snapshot, busy: true);
    try {
      await task();
      if (ref.mounted) {
        state = UsageReportState(
          snapshot: state.snapshot,
          messageKey: successKey,
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = UsageReportState(
          snapshot: state.snapshot,
          failed: true,
          messageKey: error is UsageSyncException
              ? error.messageKey
              : 'usageReadFailed',
        );
      }
    }
  }
}
