import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/notifications/notification_models.dart';
import '../controller/messages_controller.dart';
import 'message_item_card.dart';

/// 消息虚拟化滚动列表组件。
class MessagesListView extends ConsumerWidget {
  const MessagesListView({
    super.key,
    required this.messages,
    required this.deviceId,
    required this.isOnline,
  });

  final List<NotificationMessage> messages;
  final String deviceId;
  final bool isOnline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final targetId = ref.watch(targetMessageIdProvider);

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chat_bubble_2,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.t('noMessages'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.t('noMessagesDesc'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        if (!isOnline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.amber.withValues(alpha: 0.12),
            child: Row(
              children: [
                const Icon(CupertinoIcons.info_circle, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.t('offlineHistoryNotice'),
                    style: const TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              return MessageItemCard(
                key: ValueKey(msg.id ?? msg.notificationKey),
                message: msg,
                deviceId: deviceId,
                isTarget: targetId != null && msg.id == targetId,
              );
            },
          ),
        ),
      ],
    );
  }
}
