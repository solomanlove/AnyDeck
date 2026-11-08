import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/features/developer/widget/settings_developer_entry.dart';
import 'package:any_deck/features/feedback/widget/settings_feedback_entry.dart';
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
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SettingsDeveloperEntry(onCheckUpdate: () {}),
                  const Divider(height: 1),
                  const SettingsFeedbackEntry(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始状态下不应显示开发者选项列表项
      expect(find.text('Developer Options'), findsNothing);

      final versionFinder = find.byType(ListTile).first;

      // 连续点击 4 次
      for (int i = 0; i < 4; i++) {
        await tester.tap(versionFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Developer Options'), findsNothing);

      // 第 5 次点击
      await tester.tap(versionFinder);
      await tester.pumpAndSettle();

      // 成功激活开发者选项，显示无前置图标的入口条目
      expect(find.text('Developer Options'), findsOneWidget);

      // Hover 所在的整行与上下分割线贴合，三行均延伸到相同的左右边缘。
      final rows = find.byType(ListTile);
      final dividers = find.byType(Divider);
      expect(rows, findsNWidgets(3));
      expect(dividers, findsNWidgets(2));
      final versionRect = tester.getRect(rows.at(0));
      final developerRect = tester.getRect(rows.at(1));
      final feedbackRect = tester.getRect(rows.at(2));
      final upperDividerRect = tester.getRect(dividers.at(0));
      final lowerDividerRect = tester.getRect(dividers.at(1));
      expect(developerRect.left, versionRect.left);
      expect(developerRect.right, versionRect.right);
      expect(feedbackRect.left, versionRect.left);
      expect(feedbackRect.right, versionRect.right);
      expect(upperDividerRect.height, 1);
      expect(lowerDividerRect.height, 1);
      expect(upperDividerRect.top, versionRect.bottom);
      expect(upperDividerRect.bottom, developerRect.top);
      expect(lowerDividerRect.top, developerRect.bottom);
      expect(lowerDividerRect.bottom, feedbackRect.top);
      for (final row in tester.widgetList<ListTile>(rows)) {
        expect(row.leading, isNull);
      }
      expect(tester.getTopLeft(find.text('Developer Options')).dx,
          tester.getTopLeft(find.text('Feedback')).dx);

      // 推进时间以等待 Toast 提示定时器完成，避免 pending timer
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
