import 'package:flutter/material.dart';

import '../../app/l10n/app_localizations.dart';
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
      title: result.isSuccess ? null : Text(l10n.t('error')),
      scrollable: true,
      content: SelectableText(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }
}
