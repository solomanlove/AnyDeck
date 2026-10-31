import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/app_localizations.dart';
import '../../../app/settings/app_settings_controller.dart';
import '../../../app/settings/mirror_quality_preset.dart';
import '../../../app/widget/app_toast.dart';

/// 画质预设选择器；保存期间禁用重复操作，离开页面后不再更新异步 UI。
class MirrorQualityPresets extends ConsumerStatefulWidget {
  const MirrorQualityPresets({super.key});

  @override
  ConsumerState<MirrorQualityPresets> createState() =>
      _MirrorQualityPresetsState();
}

class _MirrorQualityPresetsState extends ConsumerState<MirrorQualityPresets> {
  bool _saving = false;

  Future<void> _apply(MirrorQualityPreset preset) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(appSettingsProvider.notifier)
          .setMirrorQualityPreset(preset);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          context.l10n.t('mirrorPresetSaveFailed'),
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final selected = MirrorQualityPreset.matching(settings);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t('mirrorPresetTitle'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in MirrorQualityPreset.values)
                ChoiceChip(
                  label: Text(context.l10n.t(preset.labelKey)),
                  selected: selected == preset,
                  onSelected: _saving ? null : (_) => _apply(preset),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.t(
              selected == null
                  ? 'mirrorPresetCustom'
                  : '${selected.labelKey}Desc',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.l10n.t('mirrorPresetEffect'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
