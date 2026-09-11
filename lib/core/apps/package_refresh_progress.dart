/// 全量刷新阶段；读取总数和写入缓存期间不推算百分比。
enum PackageRefreshStage { reading, enriching, saving, completed, failed }

/// 仅用于本次刷新任务的进度，不进入应用持久化缓存。
class PackageRefreshProgress {
  const PackageRefreshProgress({
    this.stage = PackageRefreshStage.reading,
    this.processed = 0,
    this.total = 0,
    this.failed = 0,
    this.error,
  });

  final PackageRefreshStage stage;
  final int processed;
  final int total;
  final int failed;
  final String? error;

  bool get finished =>
      stage == PackageRefreshStage.completed ||
      stage == PackageRefreshStage.failed;

  double? get fraction => switch (stage) {
    PackageRefreshStage.reading || PackageRefreshStage.saving => null,
    _ => total == 0 ? 1 : (processed / total).clamp(0, 1),
  };

  PackageRefreshProgress atStage(PackageRefreshStage stage, {String? error}) =>
      PackageRefreshProgress(
        stage: stage,
        processed: processed,
        total: total,
        failed: failed,
        error: error,
      );
}

typedef PackageRefreshCallback = void Function(PackageRefreshProgress progress);
