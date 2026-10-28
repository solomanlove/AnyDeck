import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme_sizes.dart';
import '../../../core/nearby_share/share_core_contract.dart';

/// 鸿蒙互联的本机身份栏；名称必须与核心对外广播身份保持一致。
class HarmonyShareIdentity extends StatelessWidget {
  const HarmonyShareIdentity({
    super.key,
    required this.enabled,
    required this.onChanged,
  });
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            child: const Icon(Icons.laptop_mac_rounded, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('harmonyShareIdentity'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.t('harmonyShareIdentityName'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          Semantics(
            label: context.l10n.t('harmonyShareReceive'),
            child: Switch(value: enabled, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

/// 仅展示核心真实忙碌态；未知字节进度时明确显示等待，不生成模拟百分比。
class HarmonyShareTransferPanel extends StatelessWidget {
  const HarmonyShareTransferPanel({
    super.key,
    required this.onCancel,
    this.progress,
    this.receiving = false,
    this.fileName,
  });
  final VoidCallback onCancel;
  final ShareCoreProgress? progress;
  final bool receiving;
  final String? fileName;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress?.fraction,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t(
                    receiving
                        ? 'harmonyShareReceivingActive'
                        : 'harmonyShareSending',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (fileName != null)
                  Text(fileName!, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  progress == null
                      ? context.l10n.t('harmonyShareWaiting')
                      : '${(progress!.fraction * 100).toStringAsFixed(1)}% · ${(progress!.bytes / 1048576).toStringAsFixed(1)} / ${(progress!.totalBytes / 1048576).toStringAsFixed(1)} MiB',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onCancel,
            child: Text(context.l10n.t('shareTestCancel')),
          ),
        ],
      ),
    ),
  );
}

/// 最近路径仅标明已完成传输，不推断方向；完整记录由后续任务模型提供。
class HarmonyShareRecent extends StatelessWidget {
  const HarmonyShareRecent({super.key, required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('harmonyShareRecent'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 14),
          if (paths.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: AppThemeSizes.radiusLarge,
              ),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.l10n.t('harmonyShareNoRecent'))),
                ],
              ),
            ),
          for (final path in paths.take(8))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(
                File(path).uri.pathSegments.last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    ),
  );
}

/// 收发共用确认面板；摘要只显示文件元数据，不读取内容。
class HarmonyShareConfirmDialog extends StatelessWidget {
  const HarmonyShareConfirmDialog({
    super.key,
    required this.receiving,
    required this.device,
    required this.summary,
  });
  final bool receiving;
  final String device;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(
        receiving ? Icons.download_rounded : Icons.near_me_outlined,
        color: colors.primary,
        size: 32,
      ),
      title: Text(
        context.l10n.t(
          receiving ? 'harmonyShareIncoming' : 'harmonyShareConfirm',
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: AppThemeSizes.radiusLarge,
              ),
              child: Text(summary),
            ),
            if (receiving) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.t('harmonyShareIncomingHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            context.l10n.t(
              receiving ? 'harmonyShareReject' : 'shareTestCancel',
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            context.l10n.t(
              receiving ? 'harmonyShareAccept' : 'harmonyShareConfirm',
            ),
          ),
        ),
      ],
    );
  }
}
