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

/// 保留回放按钮状态转换，测试不启动录制计时器或发送设备命令。
class _Recorder extends MouseTrackRecorderNotifier {
  _Recorder(super.deviceId);

  int pauses = 0;
  int resumes = 0;

  @override
  MouseTrackRecorderState build() => const MouseTrackRecorderState(
    status: MouseRecorderStatus.ready,
    recordDurationMs: 1000,
    actionCount: 2,
  );

  void showProgress() => state = state.copyWith(
    status: MouseRecorderStatus.playing,
    playProgress: 0.5,
    playActionIndex: 1,
  );

  @override
  void pausePlaying() {
    pauses++;
    state = state.copyWith(status: MouseRecorderStatus.paused);
  }

  @override
  Future<void> resumePlaying({
    int? currentWidth,
    int? currentHeight,
    double speed = 1.0,
  }) async {
    resumes++;
    state = state.copyWith(status: MouseRecorderStatus.playing);
  }
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
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MirrorMouseRecorderButton)),
        listen: false,
      );
      void expectRecorder(MouseRecorderStatus status) {
        expect(
          container.read(mouseTrackRecorderProvider('phone').notifier),
          same(recorder),
        );
        final state = container.read(mouseTrackRecorderProvider('phone'));
        expect(state.status, status);
        expect(state.playProgress, 0.5);
        expect(state.playActionIndex, 1);
        expect(state.actionCount, 2);
      }

      expectRecorder(MouseRecorderStatus.playing);
      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.pause_fill)).color,
        color.value.color,
      );
      expect(
        tester.widget<Text>(find.text('50%')).style?.color,
        color.value.color,
      );
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill));
      await tester.pumpAndSettle();
      expect(recorder.pauses, 1);
      expectRecorder(MouseRecorderStatus.paused);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).color,
        color.value.color,
      );
      expect(
        tester.widget<Text>(find.text('50% (暂停)')).style?.color,
        color.value.color,
      );
      color.value = AppThemeColor.blue;
      await tester.pumpAndSettle();
      expectRecorder(MouseRecorderStatus.paused);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.play_arrow_rounded)).color,
        color.value.color,
      );
      expect(
        tester.widget<Text>(find.text('50% (暂停)')).style?.color,
        color.value.color,
      );
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pumpAndSettle();
      expect(recorder.resumes, 1);
      expectRecorder(MouseRecorderStatus.playing);
      color.value = AppThemeColor.purple;
      await tester.pumpAndSettle();
      expectRecorder(MouseRecorderStatus.playing);
      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.pause_fill)).color,
        color.value.color,
      );
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
      var lastQuery = '';
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          lastQuery,
        );
        for (final title in [
          '启动应用',
          '重启应用',
          '冻结应用',
          '调试模式启动',
          '清除调试等待标记',
          '授予全部权限',
          '系统应用详情',
          '导出 APK',
          '恢复应用数据',
          '开启 Wi-Fi',
          '关闭 Wi-Fi',
          '开启移动网络',
          '关闭移动网络',
        ]) {
          await tester.enterText(find.byType(TextField), title);
          lastQuery = title;
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
          expect(
            tester
                .widget<Icon>(
                  find.descendant(of: item, matching: find.byType(Icon)),
                )
                .color,
            selected.color,
          );
        }
        await tester.enterText(find.byType(TextField), '清除数据并调试重启');
        lastQuery = '清除数据并调试重启';
        await tester.pumpAndSettle();
        final destructive = find.byWidgetPredicate(
          (widget) =>
              widget is MirrorAppQuickActionItem && widget.title == lastQuery,
        );
        expect(
          tester
              .widget<Icon>(
                find.descendant(of: destructive, matching: find.byType(Icon)),
              )
              .color,
          Theme.of(tester.element(destructive)).colorScheme.error,
        );
        expect(tester.element(find.byType(Dialog)), same(dialogElement));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
