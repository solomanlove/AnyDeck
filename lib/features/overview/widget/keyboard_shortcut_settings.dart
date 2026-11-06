import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/shortcuts/mirror_shortcut.dart';
import '../../../app/widget/app_toast.dart';

/// 设置页的通用与投屏快捷键列表，嵌入已有设置分组卡片使用。
/// 按键选择、禁用和恢复默认均通过 AppSettingsController 持久化。
class KeyboardShortcutSettings extends ConsumerWidget {
  const KeyboardShortcutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(
      appSettingsProvider.select((s) => s.mirrorShortcuts),
    );
    final showKey = ref.watch(
      appSettingsProvider.select((s) => s.showWindowShortcutKey),
    );
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = isMacOS ? '⌘' : 'Ctrl+';
    final controller = ref.read(appSettingsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.t('shortcutGeneral'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          _ShortcutRow(
            label: context.l10n.t('mainWindowShortcut'),
            control: DropdownButton<String>(
              key: const ValueKey('shortcut-main-window'),
              value: normalizeMainWindowShortcut(showKey),
              menuMaxHeight: 320,
              underline: const SizedBox.shrink(),
              items: [
                for (final key in mainWindowShortcutKeys)
                  DropdownMenuItem(
                    value: key,
                    child: Text('$modifier${key.toUpperCase()}'),
                  ),
              ],
              onChanged: (key) async {
                if (key != null) await controller.setShowWindowShortcut(key);
              },
            ),
          ),
          _ShortcutRow(
            label: context.l10n.t('shortcutOpenSettings'),
            control: Text('$modifier,'),
          ),
          _ShortcutRow(
            label: context.l10n.t('shortcutCloseWindow'),
            control: Text('${modifier}W'),
          ),
          _ShortcutRow(
            label: context.l10n.t('shortcutQuit'),
            control: Text('$modifier${context.l10n.t('shortcutDoubleQ')}'),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.t('shortcutMirroring'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton(
                key: const ValueKey('shortcut-reset'),
                onPressed: () =>
                    _save(context, ref, const MirrorShortcutSettings()),
                child: Text(context.l10n.t('shortcutReset')),
              ),
            ],
          ),
          Text(
            context.l10n.t('shortcutMirrorHint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          for (final action in MirrorShortcut.values)
            _ShortcutRow(
              label: context.l10n.t(action.labelKey),
              control: DropdownButton<String>(
                key: ValueKey('shortcut-${action.name}'),
                value: shortcuts.keyFor(action),
                menuMaxHeight: 320,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(context.l10n.t('shortcutDisabled')),
                  ),
                  for (final key in MirrorShortcutSettings.keys.keys)
                    DropdownMenuItem(
                      value: key,
                      child: Text(
                        '${isMacOS ? '⌘⌥' : 'Ctrl+Alt+'}${MirrorShortcutSettings.keyLabel(key)}',
                      ),
                    ),
                ],
                onChanged: (key) {
                  if (key == null) return;
                  final conflict = shortcuts.conflict(action, key);
                  if (conflict != null) {
                    AppToast.show(
                      context,
                      context.l10n
                          .t('shortcutConflict')
                          .replaceAll(
                            '{action}',
                            context.l10n.t(conflict.labelKey),
                          ),
                      isError: true,
                    );
                    return;
                  }
                  _save(context, ref, shortcuts.withKey(action, key));
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    MirrorShortcutSettings settings,
  ) async {
    try {
      await ref.read(appSettingsProvider.notifier).setMirrorShortcuts(settings);
    } catch (_) {
      if (context.mounted) {
        AppToast.show(
          context,
          context.l10n.t('shortcutSaveFailed'),
          isError: true,
        );
      }
    }
  }
}

/// 一行快捷键说明；标签可换行，右侧按键保持可读。
class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({required this.label, required this.control});

  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 16),
        control,
      ],
    ),
  );
}
