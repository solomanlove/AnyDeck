import 'package:flutter/material.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/shortcuts/keyboard_shortcut_binding.dart';
import '../../../app/shortcuts/local_shortcut_handler.dart';

/// 录入完整组合键；取消返回 null，清除返回 disabled，保存前执行 validate。
/// current 用于展示现有绑定，defaultBinding 用于恢复该操作默认值。
Future<KeyboardShortcutBinding?> showKeyboardShortcutRecorder({
  required BuildContext context,
  required String title,
  required KeyboardShortcutBinding current,
  required KeyboardShortcutBinding defaultBinding,
  required String? Function(KeyboardShortcutBinding binding) validate,
}) => showDialog<KeyboardShortcutBinding>(
  context: context,
  builder: (_) => _KeyboardShortcutRecorder(
    title: title,
    current: current,
    defaultBinding: defaultBinding,
    validate: validate,
  ),
);

class _KeyboardShortcutRecorder extends StatefulWidget {
  const _KeyboardShortcutRecorder({
    required this.title,
    required this.current,
    required this.defaultBinding,
    required this.validate,
  });

  final String title;
  final KeyboardShortcutBinding current;
  final KeyboardShortcutBinding defaultBinding;
  final String? Function(KeyboardShortcutBinding binding) validate;

  @override
  State<_KeyboardShortcutRecorder> createState() =>
      _KeyboardShortcutRecorderState();
}

class _KeyboardShortcutRecorderState extends State<_KeyboardShortcutRecorder> {
  KeyboardShortcutBinding? _candidate;
  String? _error;

  void _setCandidate(KeyboardShortcutBinding binding) => setState(() {
    _candidate = binding;
    _error = widget.validate(binding);
  });

  void _apply(KeyboardShortcutBinding binding) {
    _setCandidate(binding);
    if (_error == null) Navigator.of(context).pop(binding);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.current.label();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.t('shortcutRecordHint')),
            const SizedBox(height: 12),
            Text(
              context.l10n
                  .t('shortcutCurrent')
                  .replaceAll(
                    '{shortcut}',
                    current.isEmpty
                        ? context.l10n.t('shortcutDisabled')
                        : current,
                  ),
            ),
            const SizedBox(height: 16),
            LocalShortcutHandler(
              resolve: (event) => LocalShortcutMatch(() {
                final binding = KeyboardShortcutBinding.capture(event);
                if (binding != null) _setCandidate(binding);
              }),
              child: Builder(
                builder: (context) => OutlinedButton.icon(
                  key: const ValueKey('shortcut-record-input'),
                  onPressed: () => Focus.of(context).requestFocus(),
                  icon: const Icon(Icons.keyboard_outlined),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _candidate?.label() ??
                          context.l10n.t('shortcutPressKeys'),
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('shortcut-record-clear'),
          onPressed: () => _apply(const KeyboardShortcutBinding.disabled()),
          child: Text(context.l10n.t('shortcutClear')),
        ),
        TextButton(
          key: const ValueKey('shortcut-record-reset'),
          onPressed: () => _apply(widget.defaultBinding),
          child: Text(context.l10n.t('shortcutReset')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('shortcut-record-save'),
          onPressed: _candidate == null || _error != null
              ? null
              : () => _apply(_candidate!),
          child: Text(context.l10n.t('save')),
        ),
      ],
    );
  }
}
