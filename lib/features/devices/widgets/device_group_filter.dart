import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/device_groups/device_groups_controller.dart';
import '../../../core/providers/modules/registered_device_model.dart';
import 'device_groups_dialog.dart';

/// 设备工具栏中的分组入口，默认平台、自定义分组与管理菜单共用一处。
///
/// [selectedGroupId] 为空表示全部；[onChanged] 仅更新筛选，
/// [devices] 与 [names] 为未筛选的设备及展示名称，供管理弹窗勾选成员。
class DeviceGroupFilter extends ConsumerWidget {
  const DeviceGroupFilter({
    super.key,
    required this.selectedGroupId,
    required this.onChanged,
    required this.devices,
    required this.names,
  });

  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;
  final List<RegisteredDevice> devices;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(deviceGroupsProvider);
    final groups = (data.value ?? DeviceGroupsState()).groups;
    final selected = groups.where((group) => group.id == selectedGroupId);
    final label = selected.isEmpty
        ? context.l10n.t('deviceGroupAll')
        : selected.first.name;
    final theme = Theme.of(context);
    return PopupMenuButton<String>(
      key: const Key('deviceGroupFilter'),
      tooltip: context.l10n.t('deviceGroupFilter'),
      enabled: !data.isLoading,
      onSelected: (value) {
        if (value == '__retry') {
          ref.invalidate(deviceGroupsProvider);
        } else if (value == '__manage') {
          showDialog<void>(
            context: context,
            builder: (_) => DeviceGroupsDialog(
              devices: devices,
              names: names,
              initialGroupId: selectedGroupId,
            ),
          );
        } else {
          onChanged(value.isEmpty ? null : value);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: '',
          checked: selected.isEmpty,
          child: Text(context.l10n.t('deviceGroupAll')),
        ),
        for (final group in groups)
          CheckedPopupMenuItem(
            key: ValueKey('deviceGroupOption-${group.id}'),
            value: group.id,
            checked: group.id == selectedGroupId,
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const PopupMenuDivider(),
        if (data.hasError)
          PopupMenuItem(
            key: const Key('deviceGroupRetry'),
            value: '__retry',
            child: Text(context.l10n.t('deviceGroupRetry')),
          )
        else
          PopupMenuItem(
            key: const Key('deviceGroupManage'),
            value: '__manage',
            child: Text(context.l10n.t('deviceGroupManage')),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: theme.appColors.panelSurface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppThemeSizes.radiusMedium,
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 15,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}
