import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/features/developer/widget/settings_developer_entry.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Developer Mode & Easter Egg Tests', () {
    test('AppSettings 初始状态下 developerModeEnabled 默认为 false', () {
      const settings = AppSettings();
      expect(settings.developerModeEnabled, isFalse);

      final updated = settings.copyWith(developerModeEnabled: true);
      expect(updated.developerModeEnabled, isTrue);
    });

    testWidgets('连续点击版本号 5 次触发开启开发者模式', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [AppLocalizationsDelegate()],
            home: Scaffold(
              body: SettingsDeveloperEntry(
                onCheckUpdate: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始状态下不应显示开发者选项列表项及图标
      expect(find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right), findsNothing);

      final versionFinder = find.byType(ListTile).first;

      // 连续点击 4 次
      for (int i = 0; i < 4; i++) {
        await tester.tap(versionFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right), findsNothing);

      // 第 5 次点击
      await tester.tap(versionFinder);
      await tester.pumpAndSettle();

      // 成功激活开发者选项，应浮现入口图标与开发者选项条目
      expect(find.byIcon(CupertinoIcons.chevron_left_slash_chevron_right), findsOneWidget);
      expect(find.text('Developer Options'), findsOneWidget);

      // 推进时间以等待 Toast 提示定时器完成，避免 pending timer
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
