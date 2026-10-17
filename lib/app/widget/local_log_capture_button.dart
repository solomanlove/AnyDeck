import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/local_log_export.dart';
import '../l10n/app_localizations.dart';
import 'app_toast.dart';

/// 本地日志抓取按钮。控制台与调试页复用，自动处理保存、取消、失败及防重复点击。
class LocalLogCaptureButton extends ConsumerWidget {
  const LocalLogCaptureButton({super.key, this.iconOnly = false});

  /// 是否仅显示图标；用于空间受限的 Toolbar，完整操作名称由 Tooltip 提供。
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(localLogExportProvider);
    final label = context.l10n.t(
      busy ? 'localLogsCapturing' : 'localLogsCapture',
    );
    final onPressed = busy
        ? null
        : () async {
            try {
              final result = await ref
                  .read(localLogExportProvider.notifier)
                  .capture();
              if (!context.mounted || result == null) return;
              AppToast.show(
                context,
                context.l10n
                    .t(result.partial ? 'localLogsPartial' : 'localLogsSaved')
                    .replaceAll('{path}', result.path),
                type: result.partial
                    ? AppToastType.warning
                    : AppToastType.success,
              );
            } catch (error) {
              if (!context.mounted) return;
              AppToast.show(
                context,
                context.l10n
                    .t('localLogsFailed')
                    .replaceAll('{error}', error.toString()),
                type: AppToastType.error,
              );
            }
          };
    final icon = busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.file_download_outlined, size: 18);
    if (iconOnly) {
      return IconButton(tooltip: label, icon: icon, onPressed: onPressed);
    }
    return OutlinedButton.icon(
      icon: icon,
      label: Text(label),
      onPressed: onPressed,
    );
  }
}
