import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/theme/app_theme.dart';
import '../../../app/widget/device_os_logo_widget.dart';
import '../../../core/device_groups/device_groups_controller.dart';
import '../../../core/providers/modules/registered_device_model.dart';
import '../../overview/model/platform_distribution_type.dart';
import 'device_groups_dialog.dart';
import 'device_workspace_popup_menu.dart';

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
    return DeviceWorkspacePopupMenu<String>(
      buttonKey: const Key('deviceGroupFilter'),
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
        _menuItem(
          context,
          key: const Key('deviceGroupOption-all'),
          value: '',
          selected: selected.isEmpty,
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: context.l10n.t('deviceGroupAll'),
        ),
        for (final group in groups)
          _menuItem(
            context,
            key: ValueKey('deviceGroupOption-${group.id}'),
            value: group.id,
            selected: group.id == selectedGroupId,
            icon: _groupIcon(group.platform),
            label: group.name,
            ellipsize: !group.isBuiltIn,
          ),
        const PopupMenuDivider(),
        if (data.hasError)
          _menuItem(
            context,
            key: const Key('deviceGroupRetry'),
            value: '__retry',
            icon: const Icon(Icons.refresh, size: 18),
            label: context.l10n.t('deviceGroupRetry'),
          )
        else
          _menuItem(
            context,
            key: const Key('deviceGroupManage'),
            value: '__manage',
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: context.l10n.t('deviceGroupManage'),
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

  /// 平台组复用公共 Logo，自定义分组沿用文件夹语义。
  Widget _groupIcon(DeviceGroupPlatform? platform) => switch (platform) {
    DeviceGroupPlatform.android => buildPlatformIcon(
      PlatformDistributionType.android,
      size: 18,
    ),
    DeviceGroupPlatform.harmony => buildPlatformIcon(
      PlatformDistributionType.harmony,
      size: 18,
    ),
    DeviceGroupPlatform.ios => buildPlatformIcon(
      PlatformDistributionType.ios,
      size: 18,
    ),
    null => const Icon(Icons.folder_outlined, size: 18),
  };

  /// 图标与文字统一对齐，勾选标记置右，避免默认 Checked 菜单的额外留白。
  PopupMenuItem<String> _menuItem(
    BuildContext context, {
    required Key key,
    required String value,
    required Widget icon,
    required String label,
    bool? selected,
    bool ellipsize = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      key: key,
      value: value,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Semantics(
        selected: selected,
        child: Row(
          children: [
            IconTheme(
              data: IconThemeData(color: scheme.onSurface),
              child: SizedBox(width: 18, height: 18, child: icon),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: ellipsize ? 1 : null,
                overflow: ellipsize ? TextOverflow.ellipsis : TextOverflow.clip,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  height: 1.4,
                  color: scheme.onSurface,
                ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                child: selected
                    ? Icon(Icons.check, size: 16, color: scheme.primary)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
