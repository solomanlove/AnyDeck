import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/device_groups/device_groups_controller.dart';

/// 新建或重命名设备分组；校验与数据层共用规则，取消时不写入存储。
///
/// [groups] 为当前分组快照；[group] 为空时创建，否则编辑该自定义分组。
class DeviceGroupNameDialog extends StatefulWidget {
  const DeviceGroupNameDialog({super.key, required this.groups, this.group});

  final DeviceGroupsState groups;
  final DeviceGroup? group;

  @override
  State<DeviceGroupNameDialog> createState() => _DeviceGroupNameDialogState();
}

class _DeviceGroupNameDialogState extends State<DeviceGroupNameDialog> {
  late final _controller = TextEditingController(text: widget.group?.name);
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      context.l10n.t(
        widget.group == null ? 'deviceGroupCreate' : 'deviceGroupRename',
      ),
    ),
    content: SizedBox(
      width: 320,
      child: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('deviceGroupNameInput'),
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          validator: (value) {
            final error = widget.groups.validateName(
              value ?? '',
              excludingId: widget.group?.id,
            );
            return error == null ? null : context.l10n.t(error);
          },
          decoration: InputDecoration(
            labelText: context.l10n.t('deviceGroupName'),
            hintText: context.l10n.t('deviceGroupNameHint'),
            errorMaxLines: 3,
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(context.l10n.t('cancel')),
      ),
      FilledButton(
        key: const Key('deviceGroupNameSave'),
        onPressed: _submit,
        child: Text(context.l10n.t('save')),
      ),
    ],
  );
}
