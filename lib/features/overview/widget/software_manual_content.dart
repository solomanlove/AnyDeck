import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 软件说明书正文，覆盖各平台接入条件、MCP 配置与故障定位入口。
/// 由宿主提供滚动容器，可复用于设置弹窗和帮助页面。
class SoftwareManualContent extends StatelessWidget {
  const SoftwareManualContent({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final key in [
        'softwareOverview',
        'manualAndroid',
        'manualIos',
        'manualHarmony',
        'manualMcp',
        'manualTroubleshooting',
        'softwareNotice',
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('${key}Title'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(context.l10n.t(key)),
            ],
          ),
        ),
    ],
  );
}
