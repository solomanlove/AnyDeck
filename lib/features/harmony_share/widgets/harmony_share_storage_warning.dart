import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 记录存储错误与显式重试入口；onRetry 仅补写/重读元数据，不重发文件。
/// 局部状态防止重复点击，销毁后不更新 UI；用于首页和完整记录弹窗。
class HarmonyShareStorageWarning extends StatefulWidget {
  const HarmonyShareStorageWarning({super.key, required this.onRetry});
  final Future<bool> Function() onRetry;
  @override
  State<HarmonyShareStorageWarning> createState() =>
      _HarmonyShareStorageWarningState();
}

class _HarmonyShareStorageWarningState
    extends State<HarmonyShareStorageWarning> {
  bool _retrying = false;
  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } catch (_) {
      // 错误提示持续保留，传输任务不会因为记录重试而再次执行。
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.t('harmonyShareHistoryError'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      TextButton(
        onPressed: _retrying ? null : _retry,
        child: Text(
          context.l10n.t(
            _retrying
                ? 'harmonyShareRetryingStorage'
                : 'harmonyShareRetryStorage',
          ),
        ),
      ),
    ],
  );
}
