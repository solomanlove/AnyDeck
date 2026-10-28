import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_transfer_record.dart';
import 'harmony_share_format.dart';
import 'harmony_share_batch_details.dart';
import '../../../core/nearby_share/share_transfer_history.dart';

/// 完整任务记录行；record 为不可变元数据，不从路径推断来源。
/// onDetails/onOpen/onFolder/onRetry/onRemove 仅响应用户点击；空操作回调会隐藏对应菜单。
/// 用于首页摘要或历史列表，例如 HarmonyShareRecordTile(record: record, onDetails: ...)。
class HarmonyShareRecordTile extends StatelessWidget {
  const HarmonyShareRecordTile({
    super.key,
    required this.record,
    this.onDetails,
    this.onOpen,
    this.onFolder,
    this.onRetry,
    this.onRemove,
  });
  final ShareTransferRecord record;
  final VoidCallback? onDetails;
  final VoidCallback? onOpen;
  final VoidCallback? onFolder;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = record.createdAt.toLocal().toString().split('.').first;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        record.direction == ShareTransferDirection.send
            ? Icons.upload_rounded
            : Icons.download_rounded,
        color: record.status == ShareTransferStatus.failed
            ? colors.error
            : colors.primary,
      ),
      title: Text(
        record.fileName.isEmpty
            ? (record.fileCount > 1 ? context.l10n.t('harmonyShareBatchFiles').replaceAll('{count}', '${record.fileCount}') : context.l10n.t('harmonyShareUnknownFile'))
            : record.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${record.deviceName} · ${context.l10n.t('harmonyShareDirection_${record.direction.name}')} · ${formatShareBytes(record.bytes)}\n$time · ${context.l10n.t('harmonyShareStatus_${record.status.name}')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onDetails,
      trailing: PopupMenuButton<String>(
        tooltip: context.l10n.t('harmonyShareRecordActions'),
        onSelected: (action) => switch (action) {
          'details' => onDetails?.call(),
          'open' => onOpen?.call(),
          'folder' => onFolder?.call(),
          'retry' => onRetry?.call(),
          'remove' => onRemove?.call(),
          _ => null,
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'details',
            child: Text(context.l10n.t('harmonyShareRecordDetails')),
          ),
          if (onOpen != null)
            PopupMenuItem(
              value: 'open',
              child: Text(context.l10n.t('harmonyShareOpenFile')),
            ),
          if (onFolder != null)
            PopupMenuItem(
              value: 'folder',
              child: Text(context.l10n.t('harmonyShareOpenFolder')),
            ),
          if (onRetry != null)
            PopupMenuItem(
              value: 'retry',
              child: Text(context.l10n.t('harmonyShareRetry')),
            ),
          if (onRemove != null)
            PopupMenuItem(
              value: 'remove',
              child: Text(context.l10n.t('harmonyShareRemoveRecord')),
            ),
        ],
      ),
    );
  }
}

/// 记录详情使用可复制文本；本机 SHA-256 与远端完整性确认明确区分。
Future<void> showHarmonyShareRecordDetails(
  BuildContext context,
  ShareTransferRecord record, {
  ShareTransferHistory? history,
  Future<void> Function(ShareTransferRecord)? onOpen,
  Future<void> Function(ShareTransferRecord)? onFolder,
  Future<void> Function(ShareTransferRecord)? onRetry,
}) {
  Future<List<ShareTransferRecord>>? files;
  return showDialog<void>(
    context: context,
    builder: (_) => record.fileCount > 1 && history != null
        ? HarmonyShareBatchDetails(record: record, files: files ??= history.batchFiles(record.id), onOpen: onOpen, onFolder: onFolder, onRetry: onRetry)
        : HarmonyShareRecordDetailsDialog(record: record),
  );
}

/// record 提供详情元数据，内容可复制；不主动打开或读取磁盘文件。
/// 通常通过 showHarmonyShareRecordDetails 展示，也可直接放入 Dialog 预览主题。
class HarmonyShareRecordDetailsDialog extends StatelessWidget {
  const HarmonyShareRecordDetailsDialog({super.key, required this.record});
  final ShareTransferRecord record;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(context.l10n.t('harmonyShareRecordDetails')),
    content: SizedBox(
      width: 480,
      child: SelectableText(
        [
          record.fileName.isEmpty
              ? (record.fileCount > 1 ? context.l10n.t('harmonyShareBatchFiles').replaceAll('{count}', '${record.fileCount}') : context.l10n.t('harmonyShareUnknownFile'))
              : record.fileName,
          '${record.deviceName} · ${record.address}',
          context.l10n.t('harmonyShareDirection_${record.direction.name}'),
          record.batchId != null && record.direction == ShareTransferDirection.send && record.status != ShareTransferStatus.succeeded
              ? '${formatShareBytes(record.bytes)} · ${context.l10n.t('harmonyShareFileProgressUnknown')}'
              : '${formatShareBytes(record.transferredBytes)} / ${formatShareBytes(record.bytes)}',
          if (record.direction == ShareTransferDirection.send)
            context.l10n.t('harmonyShareRemoteHashUnknown'),
          context.l10n.t('harmonyShareStatus_${record.status.name}'),
          '${context.l10n.t('harmonyShareCreatedAt')}: ${record.createdAt.toLocal()}',
          if (record.completedAt != null)
            '${context.l10n.t('harmonyShareCompletedAt')}: ${record.completedAt!.toLocal()}',
          if (record.path != null) record.path!,
          if (record.error != null) formatShareError(record.error!, context.l10n.t),
          if (record.sha256 != null)
            '${context.l10n.t('harmonyShareLocalHash')}: ${record.sha256}',
        ].join('\n\n'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.t('harmonyShareGotIt')),
      ),
    ],
  );
}
