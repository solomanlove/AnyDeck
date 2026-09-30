part of '../dashboard_screen.dart';

/// 设备列表相关的弹窗和状态色，集中在一处便于调整交互文案。
extension _DeviceListPanelActions on _DeviceListPanelState {
  Future<void> _deleteSelectedDevices(
    BuildContext context,
    int selectedCount,
  ) async {
    final allDevices = ref.read(deviceRegistryProvider);
    final hasUsbOnline = allDevices
        .where((d) => d.isChecked && d.isOnline && d.hasUsbConnection)
        .isNotEmpty;

    final String message;
    if (hasUsbOnline) {
      message = context.l10n
          .t('batchDeleteUsbWarning')
          .replaceAll('{count}', '$selectedCount');
    } else {
      message = context.l10n
          .t('deleteSelectedDevicesConfirm')
          .replaceAll('{count}', '$selectedCount');
    }

    final confirmed = await _confirm(context, message);
    if (!context.mounted || !confirmed) {
      return;
    }

    await ref.read(deviceRegistryProvider.notifier).removeCheckedDevices();
    if (!context.mounted) {
      return;
    }

    _showSnack(
      context,
      context.l10n
          .t('selectedDevicesDeleted')
          .replaceAll('{count}', '$selectedCount'),
    );
  }

  Color _getStatusBgColor(String status) {
    return switch (status) {
      'device' => const Color(0xFFE8F5E9),
      'unauthorized' => const Color(0xFFFFF3E0),
      'offline' => const Color(0xFFF5F5F5),
      _ => const Color(0xFFF5F5F5),
    };
  }

  Color _getStatusTextColor(String status) {
    return switch (status) {
      'device' => const Color(0xFF2E7D32),
      'unauthorized' => const Color(0xFFE65100),
      'offline' => const Color(0xFF9E9E9E),
      _ => const Color(0xFF9E9E9E),
    };
  }

  String _getStatusText(BuildContext context, String status) {
    return switch (status) {
      'device' => context.l10n.t('deviceOnline'),
      'unauthorized' => context.l10n.t('deviceUnauthorized'),
      'offline' => context.l10n.t('deviceOffline'),
      _ => status,
    };
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _DeviceTextEditDialog(
        title: context.l10n.t('editDeviceName'),
        initialText: device.customName ?? device.model ?? '',
        hintText: context.l10n.t('enterDeviceName'),
        confirmLabel: context.l10n.t('confirm'),
      ),
    );

    if (name != null) {
      await ref.read(deviceRegistryProvider.notifier).setAlias(device.id, name);
    }
  }

  Future<void> _showRemarkDialog(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    final remark = await showDialog<String>(
      context: context,
      builder: (_) => _DeviceTextEditDialog(
        title: '编辑备注/用途',
        initialText: device.remark ?? '',
        hintText: '输入备注或用途',
        minLines: 3,
        maxLines: 5,
      ),
    );

    if (remark != null) {
      await ref.read(deviceRegistryProvider.notifier).updateRemark(device.id, remark);
    }
  }

  Future<void> _showTagsDialog(
    BuildContext context,
    RegisteredDevice device,
  ) async {
    final tagsString = await showDialog<String>(
      context: context,
      builder: (_) => _DeviceTextEditDialog(
        title: '编辑标签标识',
        initialText: device.tags.join(', '),
        hintText: '输入标签，用逗号分隔',
      ),
    );

    if (tagsString != null) {
      final tags = tagsString
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await ref.read(deviceRegistryProvider.notifier).updateTags(device.id, tags);
    }
  }
}

/// 设备文本信息通用编辑对话框（名称、备注、标签等）。
/// 封装为 StatefulWidget，确保 TextEditingController 在组件生命周期内规范管理，
/// 避免在 showDialog 返回后过早手动 dispose 导致 Flutter 框架在帧调度销毁时报断言错误。
class _DeviceTextEditDialog extends StatefulWidget {
  const _DeviceTextEditDialog({
    required this.title,
    required this.initialText,
    required this.hintText,
    this.confirmLabel,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String title;
  final String initialText;
  final String hintText;
  final String? confirmLabel;
  final int minLines;
  final int maxLines;

  @override
  State<_DeviceTextEditDialog> createState() => _DeviceTextEditDialogState();
}

class _DeviceTextEditDialogState extends State<_DeviceTextEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialText.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMultiline = widget.maxLines > 1;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          keyboardType: isMultiline ? TextInputType.multiline : TextInputType.text,
          textInputAction: isMultiline ? TextInputAction.newline : TextInputAction.done,
          decoration: InputDecoration(
            hintText: widget.hintText,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
          onSubmitted: isMultiline ? null : (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel ?? '确定'),
        ),
      ],
    );
  }
}
