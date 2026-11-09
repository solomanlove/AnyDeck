import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/features/developer/widget/developer_page_header.dart';
import 'package:any_deck/features/developer/widget/developer_window_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/shortcut_test_fixture.dart';

/// 使用真实设置保存方法，隔离原生加载与窗口广播。
class _EnabledSettings extends ShortcutTestSettings {
  @override
  AppSettings build() => const AppSettings(developerModeEnabled: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = ShortcutPlatformMocks();
  setUp(platform.setUp);
  tearDown(platform.tearDown);

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final width in [360.0, 900.0]) {
        testWidgets('$language $brightness $width 标题栏仅保留设置，开关在页面介绍区', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final state = ProviderContainer(
            overrides: [appSettingsProvider.overrideWith(_EnabledSettings.new)],
          );
          addTearDown(state.dispose);
          await tester.pumpWidget(
            shortcutTestApp(
              container: state,
              language: language,
              brightness: brightness,
              child: const Column(
                children: [
                  DeveloperWindowBar(),
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: DeveloperPageHeader(),
                  ),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          final bar = find.byKey(const ValueKey('developer-window-bar'));
          final header = find.byKey(const ValueKey('developer-page-header'));
          final control = find.byKey(const ValueKey('developer-mode-control'));
          final title = find.text(
            language == 'zh' ? '开发者选项' : 'Developer Options',
          );
          expect(title, findsOneWidget);
          expect(find.descendant(of: bar, matching: title), findsNothing);
          expect(
            find.descendant(of: bar, matching: find.byType(Switch)),
            findsNothing,
          );
          expect(
            find.descendant(of: header, matching: control),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(control).dy,
            greaterThan(tester.getBottomLeft(bar).dy),
          );
          if (width > 680) {
            expect(
              tester.getTopLeft(control).dx,
              greaterThan(tester.getTopRight(title).dx),
            );
          } else {
            expect(
              tester.getTopLeft(control).dy,
              greaterThan(tester.getBottomLeft(title).dy),
            );
          }
          expect(tester.takeException(), isNull);

          // 移动后的开关仍使用同一设置值并写入 Preference。
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          expect(state.read(appSettingsProvider).developerModeEnabled, isFalse);
          expect(
            (await SharedPreferences.getInstance()).getBool(
              'settings.developerModeEnabled',
            ),
            isFalse,
          );
          await tester.tap(find.byType(Switch));
          await tester.pumpAndSettle();
          expect(state.read(appSettingsProvider).developerModeEnabled, isTrue);
          AppToast.dismiss();
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('优化后的设置按钮返回原设置页面', (tester) async {
    final state = ProviderContainer(
      overrides: [appSettingsProvider.overrideWith(_EnabledSettings.new)],
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      shortcutTestApp(
        container: state,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                  body: Column(
                    children: [DeveloperWindowBar(), DeveloperPageHeader()],
                  ),
                ),
              ),
            ),
            child: const Text('open developer'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open developer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('developer-back-settings')));
    await tester.pumpAndSettle();
    expect(find.text('open developer'), findsOneWidget);
    expect(find.byType(DeveloperPageHeader), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
