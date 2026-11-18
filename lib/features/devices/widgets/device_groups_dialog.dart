import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_groups/device_groups_controller.dart';
import '../../../core/providers/modules/registered_device_model.dart';
import 'device_group_name_dialog.dart';

/// 管理默认分组与自定义分组，并按物理设备保存自定义成员。
///
/// [devices] 和 [names] 来自设备工作区的完整列表，不受当前搜索与筛选影响；
/// [initialGroupId] 用于打开时定位，默认分组仅展示自动归类结果。
class DeviceGroupsDialog extends ConsumerStatefulWidget {
  const DeviceGroupsDialog({
    super.key,
    required this.devices,
    required this.names,
    this.initialGroupId,
  });

  final List<RegisteredDevice> devices;
  final Map<String, String> names;
  final String? initialGroupId;

  @override
  ConsumerState<DeviceGroupsDialog> createState() => _DeviceGroupsDialogState();
}

class _DeviceGroupsDialogState extends ConsumerState<DeviceGroupsDialog> {
  late final _selection = ValueNotifier<String?>(widget.initialGroupId);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  /// 写入完成后再更新界面；失败时保留原成员并允许重试。
  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final message = error is ArgumentError ? error.message : null;
        setState(
          () => _error =
              message is String && message.startsWith('deviceGroupName')
              ? message
              : 'deviceGroupSaveFailed',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editName(DeviceGroupsState groups, [DeviceGroup? group]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => DeviceGroupNameDialog(groups: groups, group: group),
    );
    if (name == null || !mounted) return;
    await _mutate(() async {
      final controller = ref.read(deviceGroupsProvider.notifier);
      if (group == null) {
        _selection.value = await controller.createGroup(name);
      } else {
        await controller.renameGroup(group.id, name);
      }
    });
  }

  Future<void> _delete(DeviceGroup group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('deviceGroupDelete')),
        content: Text(
          context.l10n
              .t('deviceGroupDeleteConfirm')
              .replaceAll('{name}', group.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          FilledButton(
            key: const Key('deviceGroupDeleteConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(() async {
      await ref.read(deviceGroupsProvider.notifier).deleteGroup(group.id);
      _selection.value = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(deviceGroupsProvider);
    final groups = data.value;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(context.l10n.t('deviceGroupManage')),
        content: SizedBox(
          width: 520,
          height: 400,
          child: groups == null
              ? Center(
                  child: data.hasError
                      ? Text(context.l10n.t('deviceGroupLoadFailed'))
                      : const CircularProgressIndicator(),
                )
              : ValueListenableBuilder<String?>(
                  valueListenable: _selection,
                  builder: (context, selected, _) {
                    final group = groups.groups.firstWhere(
                      (group) => group.id == selected,
                      orElse: () => groups.groups.first,
                    );
                    return _buildContent(context, groups, group);
                  },
                ),
        ),
        actions: [
          if (_busy)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('close')),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    DeviceGroupsState groups,
    DeviceGroup group,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.l10n.t(_error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Expanded(
        child: CustomScrollView(
          slivers: [
            // 操作区与成员共用滚动，避免窄屏及大字号下固定头部挤出列表。
            SliverPadding(
              // OutlineInputBorder 浮动标签向上绘制，预留随字号缩放的空间。
              padding: EdgeInsets.only(
                top: MediaQuery.textScalerOf(context).scale(12),
              ),
              sliver: SliverToBoxAdapter(
                child: _buildHeader(context, groups, group),
              ),
            ),
            if (widget.devices.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(context.l10n.t('deviceGroupNoDevices')),
                ),
              )
            else
              SliverList.builder(
                itemCount: widget.devices.length,
                itemBuilder: (context, index) =>
                    _buildMember(groups, group, widget.devices[index]),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _buildHeader(
    BuildContext context,
    DeviceGroupsState groups,
    DeviceGroup group,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey('deviceGroupEditor-${group.id}'),
        initialValue: group.id,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: context.l10n.t('deviceGroupFilter'),
        ),
        items: [
          for (final entry in groups.groups)
            DropdownMenuItem(
              value: entry.id,
              child: Text(entry.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _busy ? null : (value) => _selection.value = value,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          TextButton.icon(
            key: const Key('deviceGroupCreate'),
            onPressed: _busy ? null : () => _editName(groups),
            icon: const Icon(Icons.add, size: 18),
            label: Text(context.l10n.t('deviceGroupCreate')),
          ),
          if (!group.isBuiltIn) ...[
            TextButton(
              key: const Key('deviceGroupRename'),
              onPressed: _busy ? null : () => _editName(groups, group),
              child: Text(context.l10n.t('deviceGroupRename')),
            ),
            TextButton(
              key: const Key('deviceGroupDelete'),
              onPressed: _busy ? null : () => _delete(group),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(context.l10n.t('deviceGroupDelete')),
            ),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Text(
        context.l10n.t(
          group.isBuiltIn ? 'deviceGroupAutomatic' : 'deviceGroupMembersHint',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _buildMember(
    DeviceGroupsState groups,
    DeviceGroup group,
    RegisteredDevice device,
  ) => CheckboxListTile(
    key: ValueKey('deviceGroupMember-${device.id}'),
    value: groups.matches(group.id, device),
    onChanged: group.isBuiltIn || _busy
        ? null
        : (value) => _mutate(
            () => ref
                .read(deviceGroupsProvider.notifier)
                .setMembership(group.id, device, value!),
          ),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    title: Text(
      widget.names[device.id] ?? device.displayName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      device.serial ?? device.id,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
