import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 用户主动查看的本地诊断弹窗；error 为原始错误，仅展示/复制，不读取文件或上传。
/// 发现页与任务详情共用，例如 showHarmonyShareErrorDetails(context, record.error!)。
Future<void> showHarmonyShareErrorDetails(BuildContext context, String error) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.l10n.t('harmonyShareErrorDetails')),
        content: SizedBox(width: 480, child: SelectableText(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.t('harmonyShareGotIt')),
          ),
        ],
      ),
    );
