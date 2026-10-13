import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/overview/model/platform_distribution_type.dart';
import 'package:any_deck/features/overview/model/harmony_version_distribution_data.dart';
import 'package:any_deck/features/overview/model/ios_version_distribution_data.dart';
import 'package:any_deck/features/overview/widget/platform_version_switcher.dart';
import 'package:any_deck/features/overview/widget/platform_version_distribution_shell_view.dart';

void main() {
  group('PlatformVersionDistribution Model Tests', () {
    test('PlatformDistributionType extension returns correct properties', () {
      expect(PlatformDistributionType.android.id, equals('android'));
      expect(PlatformDistributionType.harmony.id, equals('harmony'));
      expect(PlatformDistributionType.ios.id, equals('ios'));

      expect(PlatformDistributionType.android.displayName, equals('Android'));
      expect(PlatformDistributionType.harmony.displayName, equals('HarmonyOS'));
      expect(PlatformDistributionType.ios.displayName, equals('iOS'));

      expect(PlatformDistributionType.android.lastUpdatedDate, isNotEmpty);
      expect(PlatformDistributionType.harmony.lastUpdatedDate, equals('2026-10-07'));
      expect(PlatformDistributionType.ios.lastUpdatedDate, equals('2026-06-07'));

      expect(
        PlatformDistributionType.harmony.localizedFlagNotice('zh'),
        contains('华为官网存量 API 占比'),
      );
      expect(
        PlatformDistributionType.ios.localizedFlagNotice('en'),
        contains('Apple official adoption'),
      );
    });

    test('HarmonyVersionDistributionData contains full range down to 1.0', () {
      expect(HarmonyVersionDistributionData.items.isNotEmpty, isTrue);
      final latest = HarmonyVersionDistributionData.items.first;
      expect(latest.version, equals('7.0.0'));
      expect(latest.apiNum, equals(26));
      expect(latest.muteFlag, equals('NEW'));
      expect(latest.buildProfileConfig, contains('"runtimeOS": "HarmonyOS"'));
      expect(latest.buildProfileConfig, contains('"targetSdkVersion": "7.0.0 (26)"'));

      // 验证历史版本覆盖到 1.0
      expect(HarmonyVersionDistributionData.historyItems.isNotEmpty, isTrue);
      final firstHist = HarmonyVersionDistributionData.historyItems.last;
      expect(firstHist.version, equals('HarmonyOS 1.0'));
      expect(firstHist.shareStatus, equals('已归零'));
    });

    test('IosVersionDistributionData contains full range down to 1.0', () {
      expect(IosVersionDistributionData.items.isNotEmpty, isTrue);
      final latest = IosVersionDistributionData.items.first;
      expect(latest.version, equals('27'));
      expect(latest.badgeText, equals('最新'));
      expect(latest.matrix.any((m) => m.key == 'Xcode'), isTrue);

      // 验证历史版本覆盖到 1.0
      expect(IosVersionDistributionData.historyItems.isNotEmpty, isTrue);
      final firstHist = IosVersionDistributionData.historyItems.last;
      expect(firstHist.version, equals('1.0'));
      expect(firstHist.status, equals('已 EOL'));
    });
  });

  group('PlatformVersionSwitcher Widget Tests', () {
    testWidgets('PlatformVersionSwitcher renders 3 platforms and fires callback',
        (tester) async {
      PlatformDistributionType selected = PlatformDistributionType.android;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return PlatformVersionSwitcher(
                  selectedPlatform: selected,
                  onPlatformChanged: (newPlat) {
                    setState(() => selected = newPlat);
                  },
                );
              },
            ),
          ),
        ),
      );

      // 应当渲染三大平台名称
      expect(find.text('Android'), findsOneWidget);
      expect(find.text('HarmonyOS'), findsOneWidget);
      expect(find.text('iOS'), findsOneWidget);

      // 点击 HarmonyOS
      await tester.tap(find.text('HarmonyOS'));
      await tester.pumpAndSettle();
      expect(selected, equals(PlatformDistributionType.harmony));

      // 点击 iOS
      await tester.tap(find.text('iOS'));
      await tester.pumpAndSettle();
      expect(selected, equals(PlatformDistributionType.ios));
    });

    testWidgets('PlatformVersionDistributionShellView renders and switches tabs',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 980,
              height: 640,
              child: PlatformVersionDistributionShellView(
                initialPlatform: PlatformDistributionType.harmony,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 检查当前显示 HarmonyOS
      expect(find.text('HarmonyOS 7.0.0（当前最新）'), findsOneWidget);

      // 点击 iOS 切换到 iOS 视图
      await tester.tap(find.text('iOS'));
      await tester.pumpAndSettle();

      // 检查当前显示 iOS 27
      expect(find.text('iOS 27'), findsWidgets);
    });
  });
}
