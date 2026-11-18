import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../diagnostics/widgets/services_diagnostics_button.dart';
import 'developer_section_card.dart';

/// 开发者页面保留同一全局诊断入口，避免维护独立检查与模拟状态。
class DeveloperConnectionEnvironmentCard extends StatelessWidget {
  const DeveloperConnectionEnvironmentCard({super.key});

  @override
  Widget build(BuildContext context) {
    return DeveloperSectionCard(
      title: context.l10n.t('diagnosticsTitle'),
      subtitle: context.l10n.t('diagnosticsSubtitle'),
      icon: Icons.monitor_heart_outlined,
      children: [
        Text(
          context.l10n.t('diagnosticsDeveloperDescription'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        const Align(
          alignment: Alignment.centerLeft,
          child: ServicesDiagnosticsButton(),
        ),
      ],
    );
  }
}
