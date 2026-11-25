import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 Android 专属概览字段与平台隔离，避免真实设备查询。
void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets('三星概览展示 One UI 版本 $language $brightness', (tester) async {
        await _pumpOverview(
          tester,
          language: language,
          brightness: brightness,
          customOs: 'One UI 9.0',
        );

        expect(find.text('One UI 9.0'), findsOneWidget);
        expect(find.text('Android 17'), findsOneWidget);
        expect(find.text('API 37'), findsOneWidget);
        expect(
          find.text(language == 'zh' ? '厂商系统' : 'Manufacturer OS'),
          findsOneWidget,
        );
        expect(find.text('原生 Android'), findsNothing);
        expect(find.text('Stock Android'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      for (final customOs in ['-', '']) {
        testWidgets('缺失厂商系统显示原生 Android $customOs $language $brightness', (
          tester,
        ) async {
          await _pumpOverview(
            tester,
            language: language,
            brightness: brightness,
            customOs: customOs,
          );

          expect(
            find.text(language == 'zh' ? '原生 Android' : 'Stock Android'),
            findsOneWidget,
          );
          expect(find.text('未识别'), findsNothing);
          expect(find.text('Not detected'), findsNothing);
          expect(find.text('One UI 9.0'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }

      for (final platform in ['harmony', 'ios']) {
        testWidgets('$platform 不展示 Android 厂商系统 $language $brightness', (
          tester,
        ) async {
          await _pumpOverview(
            tester,
            language: language,
            brightness: brightness,
            customOs: 'One UI 9.0',
            platform: platform,
            pageSizeBytes: 16384,
          );

          expect(find.text('One UI 9.0'), findsNothing);
          expect(
            find.text(language == 'zh' ? '厂商系统' : 'Manufacturer OS'),
            findsNothing,
          );
          expect(
            find.text(language == 'zh' ? '原生 Android' : 'Stock Android'),
            findsNothing,
          );
          expect(find.text('16 KB'), findsNothing);
          expect(
            find.text(language == 'zh' ? '内存页大小' : 'Memory page size'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final (language, bytes, label, value, kernelLabel) in [
    ('zh', 4096, '内存页大小', '4 KB', '内核版本'),
    ('en', 16384, 'Memory page size', '16 KB', 'Kernel version'),
    ('zh', null, '内存页大小', '未知', '内核版本'),
    ('en', null, 'Memory page size', 'Unknown', 'Kernel version'),
  ]) {
    testWidgets('$language 展示内存页大小 $value', (tester) async {
      await _pumpOverview(
        tester,
        language: language,
        brightness: language == 'zh' ? Brightness.light : Brightness.dark,
        customOs: '-',
        width: language == 'zh' ? 1000 : 400,
        pageSizeBytes: bytes,
      );
      final pageSizeLabel = find.text(label);
      expect(pageSizeLabel, findsOneWidget);
      expect(find.text(value), findsOneWidget);
      expect(
        tester.getTopLeft(pageSizeLabel).dy,
        greaterThan(tester.getTopLeft(find.text(kernelLabel)).dy),
      );
      expect(tester.takeException(), isNull);
    });
  }
}

/// 使用缓存模型渲染真实概览 Widget，同时屏蔽 Root 探测和设备心跳。
Future<void> _pumpOverview(
  WidgetTester tester, {
  required String language,
  required Brightness brightness,
  required String customOs,
  String platform = 'android',
  double width = 1000,
  int? pageSizeBytes,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final isHarmony = platform == 'harmony';
  final isIos = platform == 'ios';
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceRootStatusProvider('test').overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        locale: Locale(language),
        theme: buildAppTheme(brightness),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: DeviceOverviewContent(
            device: DiscoveredDevice(
              id: 'test',
              status: 'device',
              isHarmony: isHarmony,
              isIos: isIos,
            ),
            overview: DeviceOverview.fromJson({
              'name': '测试设备',
              'brand': isHarmony
                  ? 'HUAWEI'
                  : isIos
                  ? 'Apple'
                  : 'samsung',
              'model': isIos ? 'iPhone' : 'SM-F9710',
              'serial': 'test-serial',
              'androidVersion': isHarmony
                  ? 'HarmonyOS 6'
                  : isIos
                  ? 'iOS 18'
                  : 'Android 17 (API 37)',
              'customOs': customOs,
              'pageSizeBytes': ?pageSizeBytes,
            }),
            onRefresh: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
