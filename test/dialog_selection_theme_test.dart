import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/notifications/notification_forwarding_service.dart';
import 'package:any_deck/core/notifications/notification_providers.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/messages/presentation/controller/messages_controller.dart';
import 'package:any_deck/features/messages/presentation/widgets/blocked_apps_dialog.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_controller.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:any_deck/features/screenshot/widgets/screenshot_auto_save_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 应用列表不执行设备查询，保留一个可筛出的真实屏蔽项。
class _Packages extends PackagesNotifier {
  _Packages() : super('phone');

  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncData([
    AdbPackage(name: 'dev.anydeck.notes', label: 'Notes'),
    AdbPackage(name: 'dev.anydeck.mail', label: 'Mail'),
  ]);
}

/// 只记录屏蔽操作，不创建数据库、通知桥接或真实转发服务。
class _Forwarding extends Fake implements NotificationForwardingService {
  final blocked = {'dev.anydeck.notes'};
  final calls = <(String, String, bool)>[];

  @override
  Future<void> toggleBlockApp(
    String serial,
    String packageName,
    bool block,
  ) async {
    calls.add((serial, packageName, block));
    block ? blocked.add(packageName) : blocked.remove(packageName);
  }
}

class _Settings extends AppSettingsController {
  @override
  AppSettings build() => const AppSettings(screenshotSavePath: '/captures');
}

/// 保存配置只记录调用，防止提交测试启动截图、文件写入或计时器。
class _Screenshots extends ScreenshotController {
  _Screenshots() : super('phone');
  final writes = <(bool, String, int, bool)>[];

  @override
  ScreenshotLayoutState build() => const ScreenshotLayoutState(
    isAutoSave: true,
    isAutoRefresh: true,
    autoSavePath: '/captures',
    autoRefreshInterval: 3,
  );

  @override
  void updateAutoRefreshConfig({
    required bool autoSave,
    required String savePath,
    required int intervalSeconds,
    bool startImmediately = true,
  }) {
    writes.add((autoSave, savePath, intervalSeconds, startImmediately));
  }
}

/// 使用同一 Navigator 的真实弹窗，主题变化不重新创建草稿状态。
Widget _app(
  ValueNotifier<AppThemeColor> color,
  Brightness brightness,
  void Function(BuildContext) open,
) => ValueListenableBuilder<AppThemeColor>(
  valueListenable: color,
  builder: (_, selected, _) => MaterialApp(
    theme: buildAppTheme(
      brightness,
      themeColor: selected,
    ).copyWith(platform: TargetPlatform.android),
    locale: const Locale('zh'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(
      body: Builder(
        builder: (context) =>
            TextButton(onPressed: () => open(context), child: const Text('打开')),
      ),
    ),
  ),
);

Finder _interval(String label) => find.widgetWithText(ChoiceChip, label);

/// 当前 SDK 的真实 Chip 背景由 Ink 承载，兼容旧版 Material 实现。
Color? _chipBackground(WidgetTester tester, Finder chip) {
  final material = tester.widget<Material>(
    find.descendant(of: chip, matching: find.byType(Material)).first,
  );
  if (material.color != null) return material.color;
  final ink = tester.widget<Ink>(
    find.descendant(of: chip, matching: find.byType(Ink)).first,
  );
  return (ink.decoration! as ShapeDecoration).color;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('屏蔽开关动态换色并保留筛选和真实切换回调 $brightness', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final service = _Forwarding();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            packagesProvider('phone').overrideWith(_Packages.new),
            blockedAppsProvider(
              'serial',
            ).overrideWith((ref) async => Set<String>.of(service.blocked)),
            notificationForwardingServiceProvider.overrideWithValue(service),
          ],
          child: _app(
            color,
            brightness,
            (context) => BlockedAppsDialog.show(
              context,
              deviceId: 'phone',
              serial: 'serial',
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'notes');
      await tester.pumpAndSettle();
      final dialog = tester.state(find.byType(BlockedAppsDialog));
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        final toggle = find.byType(Switch);
        expect(tester.widget<Switch>(toggle).value, isTrue);
        final paint = find.descendant(
          of: toggle,
          matching: find.byWidgetPredicate(
            (widget) => widget is CustomPaint && widget.painter != null,
          ),
        );
        expect(paint, findsOneWidget);
        expect(
          paint,
          paints..something(
            (method, arguments) =>
                method == #drawRRect &&
                (arguments[1] as Paint).color.toARGB32() ==
                    selected.color.withValues(alpha: 0.5).toARGB32(),
          ),
        );
        expect(tester.widget<Switch>(toggle).activeThumbColor, selected.color);
        expect(find.text('Mail'), findsNothing);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          'notes',
        );
        expect(tester.state(find.byType(BlockedAppsDialog)), same(dialog));
        expect(service.calls, isEmpty);
      }
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(service.calls, [('serial', 'dev.anydeck.notes', false)]);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(service.calls.last, ('serial', 'dev.anydeck.notes', true));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('截图刷新间隔实际背景文字与勾选换色，保留草稿并正确提交 $brightness', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final color = ValueNotifier(AppThemeColor.blue);
      addTearDown(color.dispose);
      final screenshots = _Screenshots();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(_Settings.new),
            screenshotLayoutControllerProvider(
              'phone',
            ).overrideWith(() => screenshots),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              // 模拟真实截图工作台持续监听，弹窗期间保留同一会话 Controller。
              ref.watch(screenshotLayoutControllerProvider('phone'));
              return _app(
                color,
                brightness,
                (context) => ScreenshotAutoSaveDialog.show(
                  context: context,
                  deviceId: 'phone',
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(_interval('5s'));
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      final dialog = tester.state(find.byType(ScreenshotAutoSaveDialog));
      for (final selected in [AppThemeColor.blue, AppThemeColor.purple]) {
        color.value = selected;
        await tester.pumpAndSettle();
        final chip = _interval('5s');
        final scheme = Theme.of(tester.element(chip)).colorScheme;
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        expect(_chipBackground(tester, chip), scheme.primaryContainer);
        expect(
          DefaultTextStyle.of(tester.element(find.text('5s'))).style.color,
          scheme.onPrimaryContainer,
        );
        expect(
          chip,
          paints..something(
            (method, arguments) =>
                method == #drawPath &&
                (arguments[1] as Paint).style == PaintingStyle.stroke &&
                (arguments[1] as Paint).color.toARGB32() ==
                    scheme.onPrimaryContainer.toARGB32(),
          ),
        );
        expect(tester.widget<ChoiceChip>(_interval('3s')).selected, isFalse);
        expect(
          tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
          isFalse,
        );
        expect(find.text('/captures'), findsOneWidget);
        expect(
          tester.state(find.byType(ScreenshotAutoSaveDialog)),
          same(dialog),
        );
        expect(screenshots.writes, isEmpty);
      }
      final l10n = AppLocalizations(const Locale('zh'));
      await tester.tap(find.text(l10n.t('saveAndApply')));
      await tester.pumpAndSettle();
      expect(screenshots.writes, [(false, '/captures', 5, true)]);
      expect(find.byType(ScreenshotAutoSaveDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
