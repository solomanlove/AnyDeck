import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/local_log_export.dart';
import '../l10n/app_localizations.dart';
import 'app_toast.dart';

/// 本地日志抓取按钮。控制台与调试页复用，自动处理保存、取消、失败及防重复点击。
class LocalLogCaptureButton extends ConsumerWidget {
  const LocalLogCaptureButton({
    super.key,
    this.iconOnly = false,
    this.iconButtonStyle,
    this.filteredLogs,
  });

  /// 是否仅显示图标；用于空间受限的 Toolbar，完整操作名称由 Tooltip 提供。
  final bool iconOnly;

  /// 控制台传入可见日志后显示范围菜单；调试页保留完整诊断抓取。
  final List<String>? filteredLogs;

  /// Icon 模式下的按钮样式，由所在 Toolbar 注入以保持同组操作视觉一致。
  final ButtonStyle? iconButtonStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(localLogExportProvider);
    final label = context.l10n.t(
      busy ? 'localLogsCapturing' : 'localLogsCapture',
    );
    Future<void> capture({bool currentFilter = false}) async {
      try {
        final result = await ref
            .read(localLogExportProvider.notifier)
            .capture(filteredLogs: currentFilter ? filteredLogs : null);
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
    }
    final onPressed = busy ? null : () => capture();
    final icon = busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.file_download_outlined, size: 18);
    if (filteredLogs != null) {
      return PopupMenuButton<bool>(
        tooltip: context.l10n.t('consoleExportLogs'),
        enabled: !busy,
        icon: icon,
        onSelected: (currentFilter) => capture(currentFilter: currentFilter),
        itemBuilder: (_) => [
          PopupMenuItem(value: true, child: Text(context.l10n
              .t('consoleExportFiltered').replaceAll('{count}', '${filteredLogs!.length}'))),
          PopupMenuItem(value: false,
              child: Text(context.l10n.t('consoleExportHistory'))),
        ],
      );
    }
    if (iconOnly) {
      return IconButton(
        tooltip: label,
        style: iconButtonStyle,
        icon: icon,
        onPressed: onPressed,
      );
    }
    return OutlinedButton.icon(
      icon: icon,
      label: Text(label),
      onPressed: onPressed,
    );
  }
}
