import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/l10n/app_localizations.dart';
import '../../../../core/notifications/notification_models.dart';
import '../../../../core/providers/app_providers.dart';
import 'message_device_badge.dart';

/// 单条通知消息展示卡片。
class MessageItemCard extends ConsumerWidget {
  const MessageItemCard({
    super.key,
    required this.deviceLabel,
    required this.message,
    required this.deviceId,
    this.isTarget = false,
  });

  final NotificationMessage message;
  final String deviceId;
  final bool isTarget;
  final String deviceLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 尝试读取应用图标缓存
    final packages = ref.watch(packagesProvider(deviceId)).value;
    String? iconPath;
    String appDisplayName = message.appName ?? '';

    if (packages != null) {
      for (final p in packages) {
        if (p.name == message.packageName) {
          iconPath = p.iconLocalPath;
          if (appDisplayName.isEmpty && p.label != null) {
            appDisplayName = p.label!;
          }
          break;
        }
      }
    }
    if (appDisplayName.isEmpty) {
      appDisplayName = message.packageName;
    }

    final cardBg = isTarget
        ? (isDark
            ? const Color(0xff09c47c).withValues(alpha: 0.20)
            : const Color(0xff09c47c).withValues(alpha: 0.12))
        : (isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03));

    final borderColor = isTarget
        ? const Color(0xff09c47c)
        : (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.08));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isTarget ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MessageDeviceBadge(label: deviceLabel),
          const SizedBox(height: 8),
          // 顶部：App 图标、名称、包名与时间
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: iconPath != null && File(iconPath).existsSync()
                      ? Image.file(
                          File(iconPath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            CupertinoIcons.app_badge,
                            size: 20,
                          ),
                        )
                      : const Icon(CupertinoIcons.app_badge, size: 20),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      appDisplayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message.packageName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (message.isRemoved) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    context.l10n.t('removedFromPhone'),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _formatTime(message.receivedTime),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (message.title.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              message.content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        now.year == time.year && now.month == time.month && now.day == time.day;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    if (isToday) {
      return '$hour:$minute';
    }
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}
