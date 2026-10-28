import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/nearby_share/harmony_share_send_queue.dart';
import 'harmony_share_format.dart';

/// 发送队列展示：items 为不可变行快照，取消回调按 id 操作，清除仅清除本次结果面板。
/// nativeBatch 使用 batchTransferredBytes 展示真实总进度，隐藏逐文件取消和推测进度。
/// cancelling 禁用重复取消；行列表限制高度并按需构建，避免 100 项撑满页面。
class HarmonyShareQueuePanel extends StatelessWidget {
  const HarmonyShareQueuePanel({
    super.key,
    required this.items,
    required this.running,
    required this.onCancel,
    required this.onCancelAll,
    required this.onClear,
    this.nativeBatch = false,
    this.batchTransferredBytes = 0,
    this.cancelling = false,
  });
  final List<ShareSendItem> items;
  final bool running;
  final ValueChanged<String> onCancel;
  final VoidCallback onCancelAll;
  final VoidCallback onClear;
  final bool nativeBatch;
  final int batchTransferredBytes;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final finished = items.where((item) => item.terminal).length;
    final bytes = nativeBatch
        ? batchTransferredBytes
        : items.fold(0, (value, item) => value + item.transferredBytes);
    final total = items.fold(0, (value, item) => value + item.file.bytes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.t('harmonyShareQueueTitle'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: cancelling
                      ? null
                      : (running ? onCancelAll : onClear),
                  child: Text(
                    context.l10n.t(
                      cancelling
                          ? 'harmonyShareCancellingBatch'
                          : running
                          ? (nativeBatch
                                ? 'harmonyShareCancelBatch'
                                : 'harmonyShareCancelAll')
                          : 'harmonyShareClearQueue',
                    ),
                  ),
                ),
              ],
            ),
            Text(
              context.l10n
                  .t('harmonyShareQueueCount')
                  .replaceAll('{done}', '$finished')
                  .replaceAll('{total}', '${items.length}'),
            ),
            if (finished > 0)
              Text(
                context.l10n
                    .t('harmonyShareQueueResults')
                    .replaceAll(
                      '{sent}',
                      '${items.where((item) => item.status == ShareSendStatus.succeeded).length}',
                    )
                    .replaceAll(
                      '{failed}',
                      '${items.where((item) => item.status == ShareSendStatus.failed).length}',
                    )
                    .replaceAll(
                      '{cancelled}',
                      '${items.where((item) => item.status == ShareSendStatus.cancelled).length}',
                    ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (nativeBatch)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.l10n.t('harmonyShareNativeBatchHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: total == 0 ? 0 : bytes / total),
            const SizedBox(height: 6),
            Text(
              '${formatShareBytes(bytes)} / ${formatShareBytes(total)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: (items.length * 78.0).clamp(78, 312),
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  final color = switch (item.status) {
                    ShareSendStatus.failed => Theme.of(
                      context,
                    ).colorScheme.error,
                    ShareSendStatus.succeeded => Theme.of(
                      context,
                    ).appColors.success,
                    _ => Theme.of(context).colorScheme.onSurfaceVariant,
                  };
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(switch (item.status) {
                      ShareSendStatus.queued => Icons.schedule_rounded,
                      ShareSendStatus.preparing => Icons.hourglass_top_rounded,
                      ShareSendStatus.transferring => Icons.upload_rounded,
                      ShareSendStatus.succeeded =>
                        Icons.check_circle_outline_rounded,
                      ShareSendStatus.failed => Icons.error_outline_rounded,
                      ShareSendStatus.cancelled => Icons.cancel_outlined,
                    }, color: color),
                    title: Text(
                      item.file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.peer.name} · ${context.l10n.t('harmonyShareQueue_${item.status.name}')} · ${nativeBatch ? formatShareBytes(item.file.bytes) : '${formatShareBytes(item.transferredBytes)} / ${formatShareBytes(item.file.bytes)}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.error != null)
                          Tooltip(
                            message: item.error!,
                            child: Text(
                              item.error!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: color),
                            ),
                          ),
                        if (!nativeBatch &&
                            item.status == ShareSendStatus.transferring)
                          LinearProgressIndicator(
                            value: item.transferredBytes / item.file.bytes,
                          ),
                      ],
                    ),
                    trailing: nativeBatch || item.terminal
                        ? null
                        : IconButton(
                            tooltip: context.l10n.t('harmonyShareCancelItem'),
                            onPressed: () => onCancel(item.id),
                            icon: const Icon(Icons.close_rounded),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
