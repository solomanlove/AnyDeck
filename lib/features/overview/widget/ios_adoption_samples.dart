import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../model/ios_version_distribution_data.dart';

/// 按统计来源、日期、样本范围分别呈现采用率，不绘制混合来源的连续柱状图。
/// onSelected 复用原详情选择流程，selectedVersion 标记当前条目。
class IosAdoptionSamples extends StatelessWidget {
  const IosAdoptionSamples({
    super.key,
    required this.selectedVersion,
    required this.onSelected,
  });

  final String selectedVersion;
  final ValueChanged<IosDistributionItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final groups = <(String, String?, String), List<IosDistributionItem>>{};
    for (final item in IosVersionDistributionData.items) {
      final key = (item.source, item.sampleDate, item.populationKey);
      groups.putIfAbsent(key, () => []).add(item);
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(l10n.t('iosVersionAdoption'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(l10n.t('iosSampleSeparation'), style: theme.textTheme.bodySmall),
        for (final group in groups.entries)
          Card(
            key: ValueKey('iosSample:${group.key}'),
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${l10n.t(group.key.$1 == 'Apple 官方' ? 'iosSampleOfficial' : 'iosSampleThirdParty')}\n'
                      '${group.key.$2 ?? l10n.t('iosSampleDateUnknown')} · ${l10n.t(group.key.$3)}',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  const Divider(),
                  for (final item in group.value)
                    ListTile(
                      dense: true,
                      selected: selectedVersion == item.version,
                      selectedTileColor: theme.colorScheme.secondaryContainer,
                      title: Text('iOS ${item.version}'),
                      subtitle: Text(item.minor),
                      trailing: Text(
                        item.share,
                        style: theme.textTheme.titleSmall,
                      ),
                      onTap: () => onSelected(item),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
