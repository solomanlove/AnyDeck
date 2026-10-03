import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/local_log_capture_button.dart';
import 'developer_section_card.dart';

/// 调试页的本地日志入口；无需连接手机即可导出当前及历史运行记录。
class DeveloperLocalLogsCard extends StatelessWidget {
  const DeveloperLocalLogsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DeveloperSectionCard(
      title: context.l10n.t('localLogsTitle'),
      subtitle: context.l10n.t('localLogsDescription'),
      icon: Icons.manage_search_outlined,
      children: [
        Text(
          context.l10n.t('localLogsPrivacy'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        const LocalLogCaptureButton(),
      ],
    );
  }
}
