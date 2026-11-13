import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 协议卡片内的名称编辑区，区分用户配置与当前手机列表中的广播名称。
///
/// [field] 编辑原始配置名 [configuredName]，避免自动消歧后缀写回用户配置。
/// [broadcastName] 仅在服务运行时传入；与配置不同时显示可复制的实际名称。
/// [broadcastNameKey] 可用于定位当前广播名称，例如 Widget 验证。
/// [isNamePending] 表示发布名称尚未确认，此时仅提示等待，不展示待发布名称。
class ReceiverNameSection extends StatelessWidget {
  const ReceiverNameSection({
    super.key,
    required this.configuredName,
    required this.field,
    this.broadcastName,
    this.broadcastNameKey,
    this.isNamePending = false,
    this.pendingNameKey,
  });

  final String configuredName;
  final Widget field;
  final String? broadcastName;
  final Key? broadcastNameKey;
  final bool isNamePending;
  final Key? pendingNameKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actualName = broadcastName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.t('receiverName'),
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        field,
        if (isNamePending) ...[
          const SizedBox(height: 10),
          Text(
            context.l10n.t('receiverNamePending'),
            key: pendingNameKey,
            style: theme.textTheme.bodySmall,
          ),
        ] else if (actualName != null && actualName != configuredName) ...[
          const SizedBox(height: 10),
          Text(
            context.l10n.t('receiverBroadcastName'),
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 3),
          SelectableText(
            actualName,
            key: broadcastNameKey,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
