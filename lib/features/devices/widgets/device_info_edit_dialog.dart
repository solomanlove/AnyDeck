import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';

/// 统一设备信息编辑对话框。
///
/// 用途：
/// 集中编辑指定设备的自定义别名、分类标签（逗号分隔）及用途备注信息；
/// 避免在设备列表中散落过多小铅笔图标，提供清晰统一的表单编辑面板。
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
    if (_isSaving) return;
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
              // 1. 设备自定义名称
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

              // 2. 标签标识
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

              // 3. 备注/用途（支持多行输入与适宜留白）
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
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.t('cancel')),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.t('confirm')),
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
