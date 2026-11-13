import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../core/airplay/airplay_server_service.dart';
import '../../../core/dlna/dlna_renderer_service.dart';

/// 展示手机端可查找的本机投屏名称，便于同一局域网内核对电脑。
///
/// 运行中的服务优先展示实际广播名；停止后展示下一次启动使用的设置名。
/// [service] 默认使用全局 DLNA 服务，测试可注入无网络的服务。
class ReceiverLocalNames extends ConsumerWidget {
  const ReceiverLocalNames({super.key, this.service});

  final DlnaRendererService? service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final session = ref.watch(airplaySessionProvider);
    final dlna = service ?? DlnaRendererService.instance;
    final airplayName =
        session != null &&
            (session.hasAnyBroadcasting ||
                session.hasAnyMirroring ||
                session.isVideoPlaying)
        ? session.serverName
        : settings.airplayServerName;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: dlna,
      builder: (context, _) => Card(
        key: const Key('receiverLocalNames'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.t('receiverLocalNames'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.t('receiverLocalNamesDesc'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _NameRow(
                label: context.l10n.t('settingsAirplay'),
                name: airplayName,
                nameKey: const Key('receiverLocalAirplayName'),
              ),
              const SizedBox(height: 10),
              _NameRow(
                label: context.l10n.t('settingsDlna'),
                name: dlna.isRunning
                    ? dlna.serverName
                    : settings.dlnaServerName,
                nameKey: const Key('receiverLocalDlnaName'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 协议标签保留固定列宽，长名称在剩余空间内自然换行并支持复制。
class _NameRow extends StatelessWidget {
  const _NameRow({
    required this.label,
    required this.name,
    required this.nameKey,
  });

  final String label;
  final String name;
  final Key nameKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SelectableText(
            name,
            key: nameKey,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
