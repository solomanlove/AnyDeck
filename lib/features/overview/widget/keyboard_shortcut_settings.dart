import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/shortcuts/mirror_shortcut.dart';
import '../../../app/widget/app_toast.dart';
import 'keyboard_shortcut_recorder.dart';

/// 设置页的通用与投屏快捷键列表，嵌入已有设置分组卡片使用。
/// 按键录入、禁用和恢复默认均通过 AppSettingsController 持久化。
class KeyboardShortcutSettings extends ConsumerWidget {
  const KeyboardShortcutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(
      appSettingsProvider.select((s) => s.mirrorShortcuts),
    );
    final mainBinding = ref.watch(
      appSettingsProvider.select((s) => s.mainWindowBinding),
    );
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = isMacOS ? '⌘' : 'Ctrl+';

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
            control: OutlinedButton(
              key: const ValueKey('shortcut-main-window'),
              onPressed: () => _editMain(context, ref),
              child: Text(
                mainBinding.isEnabled
                    ? mainBinding.label()
                    : context.l10n.t('shortcutDisabled'),
              ),
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
              control: OutlinedButton(
                key: ValueKey('shortcut-${action.name}'),
                onPressed: () => _editMirror(context, ref, action),
                child: Text(
                  shortcuts.bindingFor(action).isEnabled
                      ? shortcuts.label(action, isMacOS: isMacOS)
                      : context.l10n.t('shortcutDisabled'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _reservedError(
    BuildContext context,
    KeyboardShortcutBinding binding,
  ) {
    final reserved = binding.reservedLabelKey;
    return reserved == null
        ? null
        : context.l10n
              .t('shortcutReserved')
              .replaceAll('{action}', context.l10n.t(reserved));
  }

  Future<void> _editMirror(
    BuildContext context,
    WidgetRef ref,
    MirrorShortcut action,
  ) async {
    final binding = await showKeyboardShortcutRecorder(
      context: context,
      title: context.l10n.t(action.labelKey),
      current: ref.read(appSettingsProvider).mirrorShortcuts.bindingFor(action),
      defaultBinding: MirrorShortcutSettings.legacyBinding(action.defaultKey),
      validate: (binding) {
        final reserved = _reservedError(context, binding);
        if (reserved != null) return reserved;
        final conflict = ref
            .read(appSettingsProvider)
            .mirrorShortcuts
            .conflict(action, binding);
        return conflict == null
            ? null
            : context.l10n
                  .t('shortcutConflict')
                  .replaceAll('{action}', context.l10n.t(conflict.labelKey));
      },
    );
    if (binding == null || !context.mounted) return;
    await _persist(
      context,
      () => ref
          .read(appSettingsProvider.notifier)
          .setMirrorShortcuts(
            ref
                .read(appSettingsProvider)
                .mirrorShortcuts
                .withBinding(action, binding),
          ),
    );
  }

  Future<void> _editMain(BuildContext context, WidgetRef ref) async {
    final binding = await showKeyboardShortcutRecorder(
      context: context,
      title: context.l10n.t('mainWindowShortcut'),
      current: ref.read(appSettingsProvider).mainWindowBinding,
      defaultBinding: KeyboardShortcutBinding.primary(
        MirrorShortcutSettings.keys['1']!,
      ),
      validate: (binding) => _reservedError(context, binding),
    );
    if (binding == null || !context.mounted) return;
    await _persist(
      context,
      () =>
          ref.read(appSettingsProvider.notifier).setMainWindowShortcut(binding),
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    MirrorShortcutSettings settings,
  ) => _persist(
    context,
    () => ref.read(appSettingsProvider.notifier).setMirrorShortcuts(settings),
  );

  Future<void> _persist(
    BuildContext context,
    Future<void> Function() save,
  ) async {
    try {
      await save();
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
        Flexible(child: control),
      ],
    ),
  );
}
