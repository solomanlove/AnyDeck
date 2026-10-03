import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import 'github_feedback_dialog.dart';

/// 设置页的 GitHub 反馈入口，无参数；放在「关于与支持」列表中使用。
class SettingsFeedbackEntry extends StatelessWidget {
  const SettingsFeedbackEntry({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      Icons.feedback_outlined,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: Text(context.l10n.t('feedbackTitle')),
    subtitle: Text(context.l10n.t('feedbackSubtitle')),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: () => showDialog<void>(
      context: context,
      builder: (_) => const GithubFeedbackDialog(),
    ),
  );
}
