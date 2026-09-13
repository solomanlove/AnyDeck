import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/adb/adb_device.dart';
import '../../../../core/notifications/notification_models.dart';
import '../../../../core/notifications/notification_providers.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/usage/usage_sync_service.dart';
import '../controller/messages_controller.dart';
import 'blocked_apps_dialog.dart';

/// 消息页面的顶部工具条，集成状态切换、Companion 检查、检索与屏蔽入口。
class MessagesHeaderBar extends ConsumerWidget {
  const MessagesHeaderBar({
    super.key,
    required this.device,
    required this.serial,
    this.status,
    required this.onClearHistory,
    required this.onRefreshStatus,
  });

  final AdbDevice device;
  final String serial;
  final NotificationSessionStatus? status;
  final VoidCallback onClearHistory;
  final VoidCallback onRefreshStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final forwardingEnabled =
        ref.watch(forwardingEnabledProvider(serial)).value ?? false;
    final forwardingService =
        ref.read(notificationForwardingServiceProvider);
    ref.watch(notificationForwardingStateChangesProvider);
    final hasQueueGap = forwardingService.hasQueueGap(device.id);

    final isOnline = ref.watch(deviceOnlineProvider(device.id));
    final packages = ref.watch(packagesProvider(device.id)).value ?? [];
    final selectedPkg = ref.watch(messagesPackageFilterProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：转发开关、Companion 状态提示与操作按钮
          Row(
            children: [
              // 消息转发总开关
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.t('messageForwarding'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: forwardingEnabled && isOnline,
                    activeThumbColor: const Color(0xff09c47c),
                    onChanged: isOnline
                        ? (enabled) async {
                            await forwardingService.setForwardingEnabled(
                              device,
                              serial,
                              enabled,
                            );
                            ref.invalidate(forwardingEnabledProvider(serial));
                          }
                        : null,
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // Companion 状态提示胶囊
              if (isOnline) _buildCompanionBadge(context, ref),
              const Spacer(),
              // 屏蔽名单按钮
              OutlinedButton.icon(
                onPressed: () => BlockedAppsDialog.show(
                  context,
                  deviceId: device.id,
                  serial: serial,
                ),
                icon: const Icon(CupertinoIcons.shield, size: 16),
                label: Text(context.l10n.t('blockedApps')),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
              const SizedBox(width: 8),
              // 清空历史按钮
              IconButton(
                onPressed: onClearHistory,
                tooltip: context.l10n.t('clearMessages'),
                icon: const Icon(CupertinoIcons.trash, size: 18),
              ),
            ],
          ),
          if (hasQueueGap) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 14,
                  color: Colors.orange,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.l10n.t('queueGapWarning'),
                    style: const TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // 第二行：搜索框与应用过滤下拉列表，用 IntrinsicHeight 保证等高对齐
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: context.l10n.t('searchMessagesPlaceholder'),
                      prefixIcon:
                          const Icon(CupertinoIcons.search, size: 16),
                      // 解除 prefixIcon 默认 48px 最小高度约束，使 TextField 与下拉框等高
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 0,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (val) {
                      ref.read(messagesSearchQueryProvider.notifier).state =
                          val;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedPkg,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          context.l10n.t('allAppsMsg'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      ...packages.map((p) {
                        return DropdownMenuItem<String?>(
                          value: p.name,
                          child: Text(
                            p.label?.isNotEmpty == true
                                ? p.label!
                                : p.name,
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      ref
                          .read(messagesPackageFilterProvider.notifier)
                          .state = val;
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanionBadge(BuildContext context, WidgetRef ref) {
    final currentStatus = status;
    final isReady = currentStatus?.isReady ?? false;

    Color badgeColor = isReady ? const Color(0xff09c47c) : Colors.amber;
    String text = isReady
        ? context.l10n.t('companionInstalled')
        : (currentStatus?.rawStatus == 'permission_required'
            ? context.l10n.t('notificationListenerPermission')
            : context.l10n.t('companionStatus'));

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final syncService =
            UsageSyncService(ref.read(adbServiceProvider), ref.read(appManagementServiceProvider));
        try {
          await syncService.openCompanion(device.id);
        } catch (_) {
          await syncService.install(device.id);
        }
        onRefreshStatus();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: badgeColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 12, color: badgeColor),
          ],
        ),
      ),
    );
  }
}
