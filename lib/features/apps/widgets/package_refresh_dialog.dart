import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/apps/package_refresh_progress.dart';

/// 统一承接手动刷新和 APK 安装后的刷新，任务期间不允许关闭弹窗。
Future<void> showPackageRefreshDialog(
  BuildContext context, {
  required Future<void> Function(PackageRefreshCallback onProgress) refresh,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => PackageRefreshDialog(refresh: refresh),
);

/// 将高频进度状态限制在弹窗内部，不触发应用表格的额外重建。
class PackageRefreshDialog extends StatefulWidget {
  const PackageRefreshDialog({super.key, required this.refresh});

  final Future<void> Function(PackageRefreshCallback onProgress) refresh;

  @override
  State<PackageRefreshDialog> createState() => _PackageRefreshDialogState();
}

class _PackageRefreshDialogState extends State<PackageRefreshDialog> {
  PackageRefreshProgress _progress = const PackageRefreshProgress();

  @override
  void initState() {
    super.initState();
    // 先挂载弹窗，保证总数查询尚未开始时就有可见反馈。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_run());
    });
  }

  Future<void> _run() async {
    try {
      await widget.refresh((progress) {
        if (mounted) setState(() => _progress = progress);
      });
      if (!mounted) return;
      if (_progress.stage != PackageRefreshStage.failed &&
          _progress.failed == 0) {
        _close();
      } else if (!_progress.finished) {
        setState(() {
          _progress = _progress.atStage(PackageRefreshStage.completed);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _progress = _progress.atStage(
          PackageRefreshStage.failed,
          error: error.toString(),
        );
      });
    }
  }

  void _close() {
    final route = ModalRoute.of(context);
    final navigator = Navigator.of(context);
    // 只关闭自己的路由，避免其他弹窗覆盖后误弹出上层页面。
    if (route != null && !route.isCurrent) {
      navigator.removeRoute(route);
    } else {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _progress.finished,
      child: AlertDialog(
        title: Text(context.l10n.t('packageRefreshTitle')),
        content: PackageRefreshView(progress: _progress),
        actions: _progress.finished
            ? [
                TextButton(
                  onPressed: _close,
                  child: Text(context.l10n.t('close')),
                ),
              ]
            : null,
      ),
    );
  }
}

/// The actual UI of the progress view, reusable inline.
class PackageRefreshView extends StatelessWidget {
  const PackageRefreshView({super.key, required this.progress});

  final PackageRefreshProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stage = progress.stage;
    final statusKey = switch (stage) {
      PackageRefreshStage.reading => 'packageRefreshReading',
      PackageRefreshStage.enriching => 'packageRefreshEnriching',
      PackageRefreshStage.saving => 'packageRefreshSaving',
      PackageRefreshStage.completed => 'packageRefreshPartial',
      PackageRefreshStage.failed => 'packageRefreshFailed',
    };
    final showCount =
        progress.total > 0 || stage == PackageRefreshStage.enriching;

    return SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.t(statusKey)),
            const SizedBox(height: 16),
            SizedBox(
              height: 4,
              child: (!progress.finished)
                  ? LinearProgressIndicator(value: progress.fraction)
                  : null,
            ),
            if (showCount) ...[
              const SizedBox(height: 12),
              Text(
                l10n
                    .t('packageRefreshCount')
                    .replaceAll('{processed}', '${progress.processed}')
                    .replaceAll('{total}', '${progress.total}'),
              ),
              Visibility(
                visible: progress.fraction != null && !progress.finished,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: Text(
                  '${(progress.fraction != null ? progress.fraction! * 100 : 0).floor()}%',
                ),
              ),
            ],
            if (progress.failed > 0) ...[
              const SizedBox(height: 12),
              Text(
                l10n
                    .t('packageRefreshFailedCount')
                    .replaceAll('{count}', '${progress.failed}'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              if (progress.failedPackages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    progress.failedPackages.join('\n'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
                    ),
                  ),
                ),
            ],
            if (progress.error != null) ...[
              const SizedBox(height: 12),
              SelectableText(progress.error!),
            ],
          ],
        ),
      ),
    );
  }
}
