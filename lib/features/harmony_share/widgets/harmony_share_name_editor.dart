import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../core/nearby_share/share_local_name.dart';

/// 本机名称编辑器：value 是已保存值，disabled 表示收发或写入中。
/// onSave 只提交合法 UTF-8 名称；持久化及错误反馈由父级统一负责。
/// 用法：置于设置面板，传入 AppSettings 中的名称与保存回调。
class HarmonyShareNameEditor extends StatefulWidget {
  const HarmonyShareNameEditor({
    super.key,
    required this.value,
    required this.disabled,
    required this.onSave,
  });

  final String value;
  final bool disabled;
  final ValueChanged<String> onSave;

  @override
  State<HarmonyShareNameEditor> createState() => _NameEditorState();
}

class _NameEditorState extends State<HarmonyShareNameEditor> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant HarmonyShareNameEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final value = _controller.text;
    var valid = true;
    try {
      ShareLocalName.validate(value);
    } on FormatException {
      valid = false;
    }
    final canSave = !widget.disabled && valid && value != widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          enabled: !widget.disabled,
          onChanged: (_) => setState(() {}),
          onSubmitted: (submitted) {
            if (widget.disabled || submitted == widget.value) return;
            try {
              ShareLocalName.validate(submitted);
              widget.onSave(submitted);
            } on FormatException {
              // 非法输入继续留在编辑器展示错误，不提交给持久化层。
            }
          },
          decoration: InputDecoration(
            labelText: l10n.t('harmonyShareLocalName'),
            helperText: l10n.t('harmonyShareLocalNameHint'),
            helperMaxLines: 3,
            errorText: valid ? null : l10n.t('harmonyShareLocalNameInvalid'),
            errorMaxLines: 3,
            counterText:
                '${utf8.encode(value).length}/${ShareLocalName.maxBytes} bytes',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: canSave ? () => widget.onSave(value) : null,
              child: Text(l10n.t('harmonyShareSaveName')),
            ),
            TextButton(
              onPressed:
                  widget.disabled || widget.value == ShareLocalName.defaultName
                  ? null
                  : () => widget.onSave(ShareLocalName.defaultName),
              child: Text(l10n.t('harmonyShareResetName')),
            ),
          ],
        ),
      ],
    );
  }
}
