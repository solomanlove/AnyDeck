import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_app_quick_action_item.dart';
import 'package:any_deck/app/window/mirror/widget/mirror_app_quick_actions_dialog.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:any_deck/features/apps/widgets/fusion_mode_setting_row.dart';
import 'package:any_deck/features/control/recorder/controller/mouse_track_recorder_controller.dart';
import 'package:any_deck/features/control/recorder/widgets/mirror_mouse_recorder_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定可回放状态，测试只检查外观，不启动录制计时器和设备命令。
class _Recorder extends MouseTrackRecorderNotifier {
  _Recorder(super.deviceId);

  @override
  MouseTrackRecorderState build() => const MouseTrackRecorderState(
    status: MouseRecorderStatus.ready,
    recordDurationMs: 1000,
    actionCount: 2,
  );

  void showProgress() => state = state.copyWith(
    status: MouseRecorderStatus.playing,
    playProgress: 0.5,
  );
}

/// 在同一 Navigator 和 ProviderScope 中切换主题，覆盖已经打开的弹窗。
Widget _app(
  ValueNotifier<AppThemeColor> color,
  Brightness brightness,
  Widget home,
) {
  return ValueListenableBuilder<AppThemeColor>(
    valueListenable: color,
    builder: (_, selected, _) => MaterialApp(
      theme: buildAppTheme(brightness, themeColor: selected),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: home,
    ),
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('投屏回放和融合投屏开关跟随动态主色 $brightness', (tester) async {
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final recorder = _Recorder('phone');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mouseTrackRecorderProvider('phone').overrideWith(() => recorder),
            deviceOnlineProvider('phone').overrideWith((ref) => true),
            deviceFusionModeProvider('phone').overrideWith(
              (ref) async => const FusionModeStatus(
                FusionModeState.enabled,
                physicalDeviceKey: 'physical-phone',
              ),
            ),
          ],
          child: _app(
            color,
            brightness,
            Scaffold(
              body: Column(
                children: [
                  MirrorMouseRecorderButton(
                    deviceId: 'phone',
                    isDark: brightness == Brightness.dark,
                  ),
                  const FusionModeSettingRow(deviceId: 'phone'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        expect(
          tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).color,
          selected.color,
        );
        expect(
          tester
              .widget<CupertinoSwitch>(find.byType(CupertinoSwitch))
              .activeTrackColor,
          selected.color,
        );
      }
      recorder.showProgress();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('50%')).style?.color,
        color.value.color,
      );
      color.value = AppThemeColor.blue;
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('50%')).style?.color,
        color.value.color,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('已打开的应用快捷操作随主题更新 $brightness', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceFusionModeProvider('phone').overrideWith(
              (ref) async => const FusionModeStatus(FusionModeState.disabled),
            ),
          ],
          child: _app(
            color,
            brightness,
            Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showMirrorAppQuickActionsDialog(
                    context: context,
                    ref: ref,
                    deviceId: 'phone',
                    package: const AdbPackage(name: 'test.anydeck'),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final dialogElement = tester.element(find.byType(Dialog));
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        for (final title in ['启动应用', '授予全部权限', '开启 Wi-Fi']) {
          await tester.enterText(find.byType(TextField), title);
          await tester.pumpAndSettle();
          final item = find.byWidgetPredicate(
            (widget) =>
                widget is MirrorAppQuickActionItem && widget.title == title,
          );
          await tester.ensureVisible(item);
          await tester.pumpAndSettle();
          expect(
            tester.widget<MirrorAppQuickActionItem>(item).iconColor,
            selected.color,
          );
        }
        expect(tester.element(find.byType(Dialog)), same(dialogElement));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
