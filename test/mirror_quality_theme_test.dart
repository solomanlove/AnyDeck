import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/settings/mirror_quality_preset.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/overview/widget/mirror_quality_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅记录预设并更新内存状态，禁止偏好写入、跨窗口广播和服务启动。
class _Settings extends AppSettingsController {
  final applied = <MirrorQualityPreset>[];

  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> setMirrorQualityPreset(MirrorQualityPreset preset) async {
    applied.add(preset);
    state = state.copyWith(
      mirrorVideoBitrate: preset.bitrate,
      mirrorMaxSize: preset.maxSize,
    );
  }
}

/// 只重建 Theme，保持真实预设控件和 Provider 持续挂载。
Widget _app(
  String language,
  Brightness brightness,
  ValueNotifier<AppThemeColor> color,
  _Settings controller,
) => ProviderScope(
  overrides: [appSettingsProvider.overrideWith(() => controller)],
  child: ValueListenableBuilder<AppThemeColor>(
    valueListenable: color,
    builder: (context, selected, _) => MaterialApp(
      theme: buildAppTheme(brightness, themeColor: selected),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: const Scaffold(
        body: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: MirrorQualityPresets()),
        ),
      ),
    ),
  ),
);

/// 检查真实渲染背景、文字和 RawChip 勾选色，兼容局部配色及共享 ChipTheme。
void _expectSelection(
  WidgetTester tester,
  AppLocalizations l10n,
  MirrorQualityPreset selected,
  AppThemeColor color,
) {
  for (final preset in MirrorQualityPreset.values) {
    final finder = find.widgetWithText(ChoiceChip, l10n.t(preset.labelKey));
    expect(tester.widget<ChoiceChip>(finder).selected, preset == selected);
  }
  final finder = find.widgetWithText(ChoiceChip, l10n.t(selected.labelKey));
  final scheme = Theme.of(tester.element(finder)).colorScheme;
  expect(scheme.primary, color.color);
  final rawFinder = find.descendant(of: finder, matching: find.byType(RawChip));
  final raw = tester.widget<RawChip>(rawFinder);
  final chipTheme = ChipTheme.of(tester.element(rawFinder));
  final material = tester.widget<Material>(
    find.descendant(of: rawFinder, matching: find.byType(Material)),
  );
  // 新版 SDK 将背景移到 Ink，仍检查最终参与绘制的颜色。
  final background =
      material.color ??
      (tester
                  .widget<Ink>(
                    find.descendant(of: rawFinder, matching: find.byType(Ink)),
                  )
                  .decoration!
              as ShapeDecoration)
          .color;
  expect(background, scheme.primaryContainer);
  expect(
    DefaultTextStyle.of(
      tester.element(find.text(l10n.t(selected.labelKey))),
    ).style.color,
    scheme.onPrimaryContainer,
  );
  expect(raw.showCheckmark, isTrue);
  expect(
    raw.checkmarkColor ?? chipTheme.checkmarkColor,
    scheme.onPrimaryContainer,
  );
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('投屏画质预设实时换色并保留选择与参数 $language $brightness', (tester) async {
        final controller = _Settings();
        final color = ValueNotifier(AppThemeColor.blue);
        addTearDown(color.dispose);
        final l10n = AppLocalizations(Locale(language));
        await tester.pumpWidget(_app(language, brightness, color, controller));
        await tester.pumpAndSettle();
        final presetsState = tester.state(find.byType(MirrorQualityPresets));
        _expectSelection(
          tester,
          l10n,
          MirrorQualityPreset.balanced,
          AppThemeColor.blue,
        );
        final beforeTheme = controller.state;
        color.value = AppThemeColor.purple;
        await tester.pumpAndSettle();
        _expectSelection(
          tester,
          l10n,
          MirrorQualityPreset.balanced,
          AppThemeColor.purple,
        );
        expect(controller.state, same(beforeTheme));
        expect(controller.applied, isEmpty);

        for (final preset in [
          MirrorQualityPreset.smooth,
          MirrorQualityPreset.clear,
        ]) {
          await tester.tap(
            find.widgetWithText(ChoiceChip, l10n.t(preset.labelKey)),
          );
          await tester.pumpAndSettle();
          expect(controller.state.mirrorVideoBitrate, preset.bitrate);
          expect(controller.state.mirrorMaxSize, preset.maxSize);
          expect(MirrorQualityPreset.matching(controller.state), preset);
          _expectSelection(tester, l10n, preset, color.value);

          final settingsBeforeTheme = controller.state;
          final appliedBeforeTheme = controller.applied.length;
          color.value = color.value == AppThemeColor.blue
              ? AppThemeColor.purple
              : AppThemeColor.blue;
          await tester.pumpAndSettle();
          _expectSelection(tester, l10n, preset, color.value);
          expect(controller.state, same(settingsBeforeTheme));
          expect(controller.applied.length, appliedBeforeTheme);
          expect(
            tester.state(find.byType(MirrorQualityPresets)),
            same(presetsState),
          );
        }
        expect(controller.applied, [
          MirrorQualityPreset.smooth,
          MirrorQualityPreset.clear,
        ]);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
