import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

/// 投屏接收管理页的协议服务卡片。
///
/// [title] 与 [description] 说明协议用途，[statusLabel] 与 [statusDetail]
/// 展示当前服务状态，[value] 和 [onChanged] 控制服务启停，[content] 承载名称设置等协议配置。
class ReceiverServiceCard extends StatelessWidget {
  const ReceiverServiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.statusLabel,
    required this.statusDetail,
    required this.statusColor,
    required this.value,
    required this.onChanged,
    required this.content,
    this.switchKey,
    this.isBusy = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final String statusLabel;
  final String statusDetail;
  final Color statusColor;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget content;
  final Key? switchKey;
  final bool isBusy;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: AppThemeSizes.radiusLarge,
                  ),
                  child: Icon(
                    icon,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.appColors.mutedForeground,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isBusy)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Switch.adaptive(
                    key: switchKey,
                    value: value,
                    onChanged: onChanged,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        statusDetail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.appColors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 12), action!],
              ],
            ),
            const SizedBox(height: 20),
            content,
          ],
        ),
      ),
    );
  }
}
