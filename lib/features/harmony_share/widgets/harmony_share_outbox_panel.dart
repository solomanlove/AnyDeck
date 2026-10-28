import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/harmony_share_send_queue.dart';
import 'harmony_share_format.dart';

/// 有界待发清单；batches 为不可变批次快照，取消只作用于对应待发批次。
/// onCancelAll 取消当前及所有待发批次；本组件不启动会话或读取文件内容。
class HarmonyShareOutboxPanel extends StatelessWidget {
  const HarmonyShareOutboxPanel({
    super.key,
    required this.batches,
    required this.onCancel,
    required this.onCancelAll,
    required this.running,
    required this.onClear,
    this.succeeded = 0,
    this.failed = 0,
    this.cancelled = 0,
  });
  final List<ShareSendBatch> batches;
  final ValueChanged<String> onCancel;
  final VoidCallback onCancelAll;
  final VoidCallback onClear;
  final bool running;
  final int succeeded;
  final int failed;
  final int cancelled;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('harmonyShareOutboxTitle'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            context.l10n.t('harmonyShareOutboxHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (succeeded + failed + cancelled > 0)
            Text(
              context.l10n
                  .t('harmonyShareQueueResults')
                  .replaceAll('{sent}', '$succeeded')
                  .replaceAll('{failed}', '$failed')
                  .replaceAll('{cancelled}', '$cancelled'),
            ),
          for (final batch in batches)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: Text(
                batch.items.first.peer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                context.l10n
                    .t('harmonyShareSelectionSummary')
                    .replaceAll('{count}', '${batch.items.length}')
                    .replaceAll('{size}', formatShareBytes(batch.bytes)),
              ),
              trailing: IconButton(
                tooltip: context.l10n.t('harmonyShareCancelBatch'),
                onPressed: () => onCancel(batch.id),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: running ? onCancelAll : onClear,
              child: Text(
                context.l10n.t(
                  running
                      ? 'harmonyShareCancelOutbox'
                      : 'harmonyShareClearQueue',
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
