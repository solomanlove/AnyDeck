import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/adb/adb_environment_service.dart';

/// ADB 环境缺失提示与一键下载引导对话框。
///
/// 当应用启动自检未发现有效 ADB 环境时主动弹出，支持：
/// 1. 一键下载 Google 官方 Platform-Tools 并在本地自动解压配置；
/// 2. 展示 Homebrew 命令行安装与官网手动安装说明；
/// 3. 手动重新检测环境。
class AdbEnvironmentDialog extends ConsumerWidget {
  const AdbEnvironmentDialog({super.key});

  /// 便捷静态展示方法
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AdbEnvironmentDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final env = ref.watch(adbEnvironmentProvider);
    final isBusy = env.isBusy;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            env.isReady
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.exclamationmark_triangle_fill,
            color: env.isReady ? Colors.green : Colors.orange,
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(
            env.isReady
                ? context.l10n.t('adbInstallSuccess')
                : context.l10n.t('adbEnvironmentMissingTitle'),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 状态描述
              Text(
                env.isReady
                    ? '${context.l10n.t('adbReadyDesc')}\n${env.version}'
                    : context.l10n.t('adbEnvironmentMissingDesc'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),

              // 下载与解压进度展示
              if (env.status == AdbEnvironmentStatus.downloading ||
                  env.status == AdbEnvironmentStatus.extracting) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            env.status == AdbEnvironmentStatus.extracting
                                ? context.l10n.t('adbExtracting')
                                : context.l10n
                                    .t('adbDownloading')
                                    .replaceAll(
                                      '{progress}',
                                      '${(env.downloadProgress * 100).toInt()}',
                                    ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${(env.downloadProgress * 100).toInt()}%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: env.downloadProgress > 0 ? env.downloadProgress : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 错误信息展示
              if (env.status == AdbEnvironmentStatus.failed &&
                  env.errorMessage.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${context.l10n.t('adbInstallFailed')}: ${env.errorMessage}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 若环境尚未就绪且未处于安装中，提供选项引导
              if (!env.isReady && !isBusy) ...[
                // 推荐选项：一键下载官方 Platform-Tools
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: theme.colorScheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.l10n.t('adbOneClickDownload'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.t('adbOneClickDownloadDesc'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(CupertinoIcons.cloud_download, size: 18),
                        label: Text(context.l10n.t('adbOneClickDownloadAction')),
                        onPressed: () {
                          ref
                              .read(adbEnvironmentProvider.notifier)
                              .downloadAndInstall();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 备选方式：命令行或手动安装
                Text(
                  context.l10n.t('adbManualInstallGuide'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.terminal, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'brew install android-platform-tools',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 16),
                        tooltip: context.l10n.t('adbCopyCommand'),
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(
                              text: 'brew install android-platform-tools',
                            ),
                          );
                          AppToast.show(
                            context,
                            context.l10n.t('adbCopied'),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!isBusy) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              env.isReady ? context.l10n.t('confirm') : context.l10n.t('close'),
            ),
          ),
          if (!env.isReady)
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.refresh, size: 16),
              label: Text(context.l10n.t('adbRecheck')),
              onPressed: () async {
                final result = await ref
                    .read(adbEnvironmentProvider.notifier)
                    .check();
                if (context.mounted && result.isReady) {
                  AppToast.show(context, context.l10n.t('adbInstallSuccess'));
                }
              },
            ),
        ],
      ],
    );
  }
}
