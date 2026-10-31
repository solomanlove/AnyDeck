import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证产品名称与硬件型号独立展示、复制及旧缓存兼容，不启动设备查询。
void main() {
  for (final width in [1000.0, 800.0, 600.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('产品名称与型号同时展示 $width $language', (tester) async {
        await _pumpOverview(tester, width: width, language: language);

        final name = find.text('荣耀Magic V6');
        final model = find.text('PNM-AN10');
        expect(name, findsOneWidget);
        expect(model, findsOneWidget);
        expect(find.text('HONOR'), findsOneWidget);
        expect(find.text(language == 'zh' ? '型号' : 'Model'), findsOneWidget);
        final namePosition = tester.getTopLeft(name);
        final modelPosition = tester.getTopLeft(model);
        if (width >= 800) {
          expect(namePosition.dx, lessThan(modelPosition.dx));
          expect(namePosition.dy, closeTo(modelPosition.dy, 1));
        } else {
          expect(namePosition.dy, lessThan(modelPosition.dy));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('产品名称与型号可分别复制原始值', (tester) async {
    final copied = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpOverview(tester);

    await tester.tap(find.text('PNM-AN10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('荣耀Magic V6'));
    await tester.pumpAndSettle();

    expect(copied, ['PNM-AN10', '荣耀Magic V6']);
    // 推进轻提示的自动关闭计时，避免测试结束后残留 Timer。
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final model in [null, '', '   ']) {
    testWidgets('型号缺失时保留产品名称 $model', (tester) async {
      await _pumpOverview(tester, model: model);

      expect(find.text('荣耀Magic V6'), findsOneWidget);
      expect(find.text('HONOR'), findsOneWidget);
      expect(find.text('型号'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('HarmonyOS 保留独立产品名称与型号', (tester) async {
    await _pumpOverview(
      tester,
      isHarmony: true,
      name: 'HUAWEI nova 12 Ultra',
      model: 'ADA-AL00U',
      brand: 'HUAWEI',
    );

    expect(find.text('HUAWEI nova 12 Ultra'), findsOneWidget);
    expect(find.text('ADA-AL00U'), findsOneWidget);
    expect(find.text('型号'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 用已解析的概览数据渲染摘要，隔离 Root 检测和设备心跳。
Future<void> _pumpOverview(
  WidgetTester tester, {
  double width = 1000,
  String language = 'zh',
  String name = '荣耀Magic V6',
  String? model = 'PNM-AN10',
  String brand = 'HONOR',
  bool isHarmony = false,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceRootStatusProvider('test').overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        locale: Locale(language),
        theme: ThemeData(
          brightness: language == 'zh' ? Brightness.light : Brightness.dark,
        ),
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
            ),
            overview: DeviceOverview.fromJson({
              'name': name,
              'brand': brand,
              'model': ?model,
              'serial': 'test-serial',
              'androidId': 'test-android-id',
              'androidVersion': isHarmony
                  ? 'HarmonyOS 6'
                  : 'Android 16 (API 36)',
            }),
            onRefresh: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
