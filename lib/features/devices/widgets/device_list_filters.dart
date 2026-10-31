import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';

/// 设备列表筛选栏；展示总量与在线数量，搜索和在线开关由宿主持有。
class DeviceListFilters extends StatelessWidget {
  const DeviceListFilters({
    super.key,
    required this.controller,
    required this.onlineCount,
    required this.totalCount,
    required this.onlineOnly,
    required this.onOnlineOnlyChanged,
    required this.onSearchChanged,
  });

  final TextEditingController controller;
  final int onlineCount;
  final int totalCount;
  final bool onlineOnly;
  final ValueChanged<bool> onOnlineOnlyChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.l10n
              .t('deviceListSummary')
              .replaceAll('{online}', '$onlineCount')
              .replaceAll('{offline}', '${totalCount - onlineCount}')
              .replaceAll('{total}', '$totalCount'),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            key: const Key('deviceListSearch'),
            controller: controller,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: context.l10n.t('deviceListSearchHint'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: context.l10n.t('clear'),
                onPressed: () {
                  controller.clear();
                  onSearchChanged('');
                },
                icon: const Icon(Icons.close, size: 16),
              ),
            ),
          ),
        ),
        FilterChip(
          key: const Key('deviceListOnlineOnly'),
          label: Text(context.l10n.t('deviceListOnlineOnly')),
          selected: onlineOnly,
          onSelected: onOnlineOnlyChanged,
        ),
      ],
    ),
  );
}
