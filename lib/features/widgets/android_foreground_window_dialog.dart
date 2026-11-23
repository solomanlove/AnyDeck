import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';
import '../../app/theme/app_theme_sizes.dart';
import '../../core/adb/adb_result.dart';

/// 控制页和投屏工具栏共用的 Android 前台窗口弹窗。
///
/// 将前台窗口查询返回的 [result] 传入 showDialog 的 builder，即可选择和复制组件名。
class AndroidForegroundWindowDialog extends StatelessWidget {
  const AndroidForegroundWindowDialog({super.key, required this.result});

  /// 查询结果，成功时 stdout 每行包含一个组件名，空值表示没有可识别的窗口。
  final AdbResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = result.isSuccess && result.stdout.isEmpty
        ? l10n.t('foregroundUnavailable')
        : result.message;
    return AlertDialog(
      semanticLabel: l10n.t('focus'),
      alignment: Alignment.center,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 520),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: const RoundedRectangleBorder(
        borderRadius: AppThemeSizes.radiusLarge,
      ),
      title: result.isSuccess
          ? null
          : Text(l10n.t('error'), textAlign: TextAlign.center),
      scrollable: true,
      contentPadding: EdgeInsets.fromLTRB(
        24,
        result.isSuccess ? 24 : 8,
        24,
        12,
      ),
      content: SelectableText(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }
}
