import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_transfer_record.dart';
import 'harmony_share_record_tile.dart';
import 'harmony_share_storage_warning.dart';
import '../../../core/nearby_share/share_transfer_history.dart';

/// 首页最近完整任务摘要；records 最多展示 8 条，storageError 控制存储异常提示。
/// onHistory 打开完整列表，onOpen/onFolder/onRetry 由上层处理路径和确认流程。
/// 用于主页：HarmonyShareHistoryRecent(records: history.recent, onHistory: ..., ...)。
class HarmonyShareHistoryRecent extends StatelessWidget {
  const HarmonyShareHistoryRecent({
    super.key,
    required this.records,
    required this.onHistory,
    required this.onOpen,
    required this.onFolder,
    required this.onRetry,
    this.storageError = false,
    this.history,
  });
  final List<ShareTransferRecord> records;
  final VoidCallback onHistory;
  final Future<void> Function(ShareTransferRecord) onOpen;
  final Future<void> Function(ShareTransferRecord) onFolder;
  final Future<void> Function(ShareTransferRecord) onRetry;
  final bool storageError;
  final ShareTransferHistory? history;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.t('harmonyShareRecent'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: onHistory,
                child: Text(context.l10n.t('harmonyShareHistory')),
              ),
            ],
          ),
          if (storageError && history != null)
            HarmonyShareStorageWarning(onRetry: history!.retryPending)
          else if (storageError)
            Text(
              context.l10n.t('harmonyShareHistoryError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(context.l10n.t('harmonyShareNoRecent')),
            ),
          for (final record in records.take(8))
            HarmonyShareRecordTile(
              record: record,
              onDetails: () => showHarmonyShareRecordDetails(context, record, history: history, onOpen: onOpen, onFolder: onFolder, onRetry: onRetry),
              onOpen: record.path == null || record.fileCount > 1 ? null : () => onOpen(record),
              onFolder: record.path == null ? null : () => onFolder(record),
              onRetry: record.canRetry ? () => onRetry(record) : null,
            ),
        ],
      ),
    ),
  );
}
