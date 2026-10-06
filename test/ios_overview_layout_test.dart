import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/ios/ios_overview_service.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 iOS 字段来源、平台标签及响应式布局，不启动桌面程序。
void main() {
  for (final width in [1000.0, 400.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('iOS 概览 $width $language', (tester) async {
        tester.view.physicalSize = Size(width, 2000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final overview = IosOverviewService.parse(
          {
            'ProductType': 'iPhone8,1',
            'DeviceName': '测试 iPhone',
            'ProductVersion': '15.8.8',
            'SerialNumber': 'real-serial',
            'CPUArchitecture': 'arm64',
            'BuildVersion': '19H422',
            'instruments:hardwareInformation': {'numberOfCpus': 2},
          },
          {'TotalBytes': 64000000000, 'FreeBytes': 40000000000},
          fallbackName: 'fallback',
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: Locale(language),
              theme: ThemeData(
                brightness: language == 'zh'
                    ? Brightness.light
                    : Brightness.dark,
              ),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: DeviceOverviewContent(
                  device: const AdbDevice(
                    id: 'udid-not-serial',
                    status: 'device',
                    isIos: true,
                  ),
                  overview: overview,
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('测试 iPhone'), findsOneWidget);
        expect(find.text('iPhone 6s (iPhone8,1)'), findsOneWidget);
        expect(find.text('real-serial'), findsOneWidget);
        expect(find.text('24.00 GB / 64.00 GB'), findsOneWidget);
        expect(find.text('750 × 1334'), findsOneWidget);
        expect(find.text('326 PPI'), findsOneWidget);
        expect(
          find.text(
            language == 'zh'
                ? '物理分辨率（型号规格）'
                : 'Physical resolution (model specification)',
          ),
          findsOneWidget,
        );
        expect(find.text('Darwin'), findsNothing);
        expect(
          find.text(language == 'zh' ? '屏幕逻辑密度' : 'Logical density'),
          findsNothing,
        );
        expect(
          find.text(
            language == 'zh'
                ? '实时 RAM 用量尚未读取'
                : 'Live RAM usage has not been read',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
