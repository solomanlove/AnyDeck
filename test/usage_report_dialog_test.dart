import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/usage/usage_snapshot.dart';
import 'package:any_deck/features/apps/controller/usage_report_controller.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/usage_fixture.dart';

/// 固定快照与已有 App 元数据，避免测试触发 ADB 或重新获取图标。
class FixedUsageController extends UsageReportController {
  FixedUsageController() : super('test');
  @override
  UsageReportState build() =>
      UsageReportState(snapshot: UsageSnapshot.fromJson(usageFixture()));
}

class UsagePackagesNotifier extends PackagesNotifier {
  UsagePackagesNotifier() : super('test');
  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncValue.data([
    AdbPackage(name: 'com.example.a', label: 'Existing cached app'),
  ]);
}

void main() {
  for (final locale in ['zh', 'en']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('使用时长弹窗复用名称与离线快照 $locale $brightness', (tester) async {
        tester.view.physicalSize = const Size(720, 680);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              usageReportProvider(
                'test',
              ).overrideWith(FixedUsageController.new),
              packagesProvider('test').overrideWith(UsagePackagesNotifier.new),
              deviceOnlineProvider('test').overrideWith((ref) => false),
            ],
            child: MaterialApp(
              locale: Locale(locale),
              theme: ThemeData(brightness: brightness),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              home: const Scaffold(body: UsageReportDialog(deviceId: 'test')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final sync = find.widgetWithText(
          FilledButton,
          locale == 'zh' ? '同步使用时长' : 'Sync usage',
        );
        expect(tester.widget<FilledButton>(sync).onPressed, isNull);
        await tester.scrollUntilVisible(
          find.text('Existing cached app'),
          150,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text('Existing cached app'), findsOneWidget);
        expect(find.text('0:40:00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
