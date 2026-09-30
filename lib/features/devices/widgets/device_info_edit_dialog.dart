import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/widget/app_toast.dart';
import '../../../core/providers/app_providers.dart';

/// 统一设备信息编辑对话框。
///
/// 用途：
/// 集中展示设备的硬件与网络详细信息（设备号、IP 地址、型号、系统版本等），
/// 编辑指定设备的自定义别名、分类标签（逗号分隔）及用途备注信息，
/// 并在弹窗左下角提供快捷删除设备的功能。
///
/// 参数：
/// - [device]：要编辑的目标注册设备对象。
class DeviceInfoEditDialog extends ConsumerStatefulWidget {
  const DeviceInfoEditDialog({
    super.key,
    required this.device,
  });

  /// 目标设备对象
  final RegisteredDevice device;

  @override
  ConsumerState<DeviceInfoEditDialog> createState() =>
      _DeviceInfoEditDialogState();
}

class _DeviceInfoEditDialogState extends ConsumerState<DeviceInfoEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _tagsController;
  late final TextEditingController _remarkController;
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.device.customName ?? widget.device.displayName,
    );
    _tagsController = TextEditingController(
      text: widget.device.tags.join(', '),
    );
    _remarkController = TextEditingController(
      text: widget.device.remark ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagsController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (_isSaving || _isDeleting) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      final tagsText = _tagsController.text.trim();
      final remark = _remarkController.text.trim();

      // 解析逗号分隔的标签列表
      final tags = tagsText
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final notifier = ref.read(deviceRegistryProvider.notifier);

      // 批量更新别名、标签和备注信息
      await notifier.setAlias(widget.device.id, name);
      await notifier.updateTags(widget.device.id, tags);
      await notifier.updateRemark(widget.device.id, remark);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 确认并删除当前设备，若设备正处于物理 USB 在线连接状态则给予警告提示
  Future<void> _handleDelete() async {
    final l10n = context.l10n;
    final device = widget.device;
    final isUsbOnline = device.isOnline && device.hasUsbConnection;
    final title = isUsbOnline
        ? l10n.t('usbConnectedDeleteWarningTitle')
        : l10n.t('confirmDeleteDeviceTitle');
    final message = isUsbOnline
        ? l10n.t('usbConnectedDeleteWarning')
        : l10n
            .t('confirmDeleteDeviceMessage')
            .replaceAll('{name}', device.displayName);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      try {
        await ref.read(deviceRegistryProvider.notifier).removeDevice(device.id);
        if (mounted) {
          AppToast.show(context, l10n.t('deviceDeletedSuccess'));
          Navigator.of(context).pop(true);
        }
      } finally {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.edit_note_rounded,
            color: theme.colorScheme.primary,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(l10n.t('editDeviceInfo')),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 设备硬件与网络详细信息卡片
              _buildDeviceInfoSection(context),
              const SizedBox(height: 16),

              // 2. 设备自定义名称
              _buildFieldLabel(l10n.t('deviceNameCol')),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.t('enterDeviceName'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. 标签标识
              _buildFieldLabel(l10n.t('deviceTagsCol')),
              const SizedBox(height: 6),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  hintText: '输入标签，多个用逗号隔开（如：测试机, 主力机）',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. 备注/用途（支持多行输入与适宜留白）
              _buildFieldLabel(l10n.t('deviceRemarkCol')),
              const SizedBox(height: 6),
              TextField(
                controller: _remarkController,
                minLines: 3,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '输入设备备注或具体用途说明',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        // 左下角：删除设备按钮
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: (_isSaving || _isDeleting) ? null : _handleDelete,
          icon: _isDeleting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.error,
                  ),
                )
              : const Icon(CupertinoIcons.trash, size: 16),
          label: Text(l10n.t('delete')),
        ),
        // 右下角：取消与保存操作按钮
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: (_isSaving || _isDeleting)
                  ? null
                  : () => Navigator.of(context).pop(),
              child: Text(l10n.t('cancel')),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: (_isSaving || _isDeleting) ? null : _handleSave,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.t('confirm')),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建设备硬件与网络详细信息卡片
  Widget _buildDeviceInfoSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final device = widget.device;

    // 优先显示物理真实硬件序列号，若为空则显示通信 ID
    final serialText = (device.serial != null && device.serial!.isNotEmpty)
        ? device.serial!
        : device.id;
    final ipText = device.wifiIp ??
        (device.ipAddress != null && device.ipAddress!.isNotEmpty
            ? device.ipAddress!
            : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.35)
              : const Color(0xFFE1E4E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.perm_device_info_rounded,
                size: 15,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '设备详细信息',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              // 在线/离线状态标识
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (device.isOnline ? Colors.green : Colors.grey)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: device.isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      device.isOnline ? '在线' : '离线',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: device.isOnline ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
            context,
            label: '设备号',
            value: serialText,
            canCopy: true,
          ),
          if (device.serial != null &&
              device.serial!.isNotEmpty &&
              device.serial != device.id) ...[
            const SizedBox(height: 6),
            _buildInfoRow(
              context,
              label: '通信标识',
              value: device.id,
              canCopy: true,
            ),
          ],
          const SizedBox(height: 6),
          _buildInfoRow(
            context,
            label: 'IP 地址',
            value: ipText ?? '未获取',
            canCopy: ipText != null,
          ),
          if (device.model != null && device.model!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildInfoRow(
              context,
              label: '设备型号',
              value: device.model!.replaceAll('_', ' '),
            ),
          ],
          if (device.androidVersion != null &&
              device.androidVersion!.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildInfoRow(
              context,
              label: '系统版本',
              value: device.androidVersion!,
            ),
          ],
        ],
      ),
    );
  }

  /// 单项设备详细属性行，支持文本划选与一键快速复制到剪贴板
  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    bool canCopy = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : const Color(0xFF57606A),
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (canCopy)
          IconButton(
            icon: const Icon(CupertinoIcons.doc_on_doc, size: 13),
            tooltip: '复制 $label',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            splashRadius: 12,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              AppToast.show(context, '$label已复制');
            },
          ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
