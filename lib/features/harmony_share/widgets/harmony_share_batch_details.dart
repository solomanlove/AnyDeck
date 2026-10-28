import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_transfer_record.dart';
import 'harmony_share_record_tile.dart';
import 'harmony_share_format.dart';
import 'harmony_share_error_details.dart';

/// 批次详情：record 为摘要，files 为打开时一次性加载的清单，不在 rebuild 重发查询。
/// onOpen/onFolder/onRetry 仅响应显式点击；onRetry 只用于可重试的发送文件。
/// 用法由 showHarmonyShareRecordDetails 统一创建。
class HarmonyShareBatchDetails extends StatelessWidget {
  const HarmonyShareBatchDetails({
    super.key,
    required this.record,
    required this.files,
    this.onOpen,
    this.onFolder,
    this.onRetry,
  });
  final ShareTransferRecord record;
  final Future<List<ShareTransferRecord>> files;
  final Future<void> Function(ShareTransferRecord)? onOpen;
  final Future<void> Function(ShareTransferRecord)? onFolder;
  final Future<void> Function(ShareTransferRecord)? onRetry;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.l10n
          .t('harmonyShareBatchFiles')
          .replaceAll('{count}', '${record.fileCount}'),
    ),
    content: SizedBox(
      width: 560,
      height: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${record.deviceName} · ${formatShareBytes(record.bytes)} · ${context.l10n.t('harmonyShareStatus_${record.status.name}')}',
          ),
          if (record.direction == ShareTransferDirection.send)
            Text(context.l10n.t('harmonyShareRemoteHashUnknown')),
          if (record.error != null)
            Text(formatShareError(record.error!, context.l10n.t)),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<ShareTransferRecord>>(
              future: files,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(context.l10n.t('harmonyShareHistoryError'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.isEmpty) {
                  return Text(context.l10n.t('harmonyShareBatchUnknownFiles'));
                }
                return Column(children: [
                  if (snapshot.data!.length < record.fileCount)
                    Text(context.l10n.t('harmonySharePartialFileList')),
                  Expanded(child: ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final file = snapshot.data![index];
                    return HarmonyShareRecordTile(
                      record: file,
                      onDetails: () =>
                          showHarmonyShareRecordDetails(context, file),
                      onOpen: onOpen == null ? null : () => onOpen!(file),
                      onFolder: onFolder == null ? null : () => onFolder!(file),
                      onRetry: onRetry == null || !file.canRetry
                          ? null
                          : () => onRetry!(file),
                    );
                  },
                  )),
                ]);
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (record.error != null)
        TextButton(
          onPressed: () => showHarmonyShareErrorDetails(context, record.error!),
          child: Text(context.l10n.t('harmonyShareErrorDetails')),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.t('harmonyShareGotIt')),
      ),
    ],
  );
}
