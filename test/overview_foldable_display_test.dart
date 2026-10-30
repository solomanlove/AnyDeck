import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证屏幕详情的双屏标签、当前屏幕数值及离线缓存展示。
void main() {
  for (final width in [1000.0, 600.0]) {
    for (final language in ['zh', 'en']) {
      testWidgets('折叠机屏幕详情 $width $language', (tester) async {
        await _pumpOverview(tester, width: width, language: language);

        expect(
          find.text(language == 'zh' ? '内屏分辨率' : 'Inner screen resolution'),
          findsOneWidget,
        );
        expect(
          find.text(language == 'zh' ? '外屏分辨率' : 'Outer screen resolution'),
          findsOneWidget,
        );
        expect(
          find.text(language == 'zh' ? '当前屏幕分辨率' : 'Current screen resolution'),
          findsOneWidget,
        );
        expect(find.text('2352x2172'), findsOneWidget);
        expect(find.text('2420x1080'), findsOneWidget);
        expect(find.text('1200x1080 (480dpi)'), findsOneWidget);
        expect(
          find.text(language == 'zh' ? '物理分辨率' : 'Physical resolution'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('离线缓存仍保留双屏分辨率', (tester) async {
    await _pumpOverview(tester, online: false);
    expect(find.text('2352x2172'), findsOneWidget);
    expect(find.text('2420x1080'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通设备和旧缓存继续显示原来的分辨率行', (tester) async {
    await _pumpOverview(tester, foldable: false);
    expect(find.text('物理分辨率'), findsOneWidget);
    expect(find.text('分辨率'), findsOneWidget);
    expect(find.text('2352x2172 (480dpi)'), findsOneWidget);
    expect(find.text('内屏分辨率'), findsNothing);
    expect(find.text('外屏分辨率'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内外屏分辨率支持分别点击复制', (tester) async {
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
    for (final value in ['2352x2172', '2420x1080']) {
      await tester.tap(find.text(value));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }
    expect(copied, ['2352x2172', '2420x1080']);
    expect(tester.takeException(), isNull);
  });
}

/// 直接渲染包含缓存字段的概览，不启动 ADB 或其他 Tab 的原生插件。
Future<void> _pumpOverview(
  WidgetTester tester, {
  double width = 1000,
  String language = 'zh',
  bool online = true,
  bool foldable = true,
}) async {
  tester.view.physicalSize = Size(width, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceRootStatusProvider('foldable').overrideWith((ref) async => false),
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
            device: AdbDevice(
              id: 'foldable',
              status: online ? 'device' : 'offline',
            ),
            overview: DeviceOverview.fromJson({
              'name': '荣耀Magic V6',
              'brand': 'HONOR',
              'androidVersion': 'Android 16 (API 36)',
              'physicalResolution': '2352x2172 (480dpi)',
              'resolution': '1200x1080 (480dpi)',
              'logicalDensity': '3x (xxhdpi)',
              'refreshRate': '120 Hz',
              if (foldable)
                'foldableDisplays': {
                  'innerResolution': '2352x2172',
                  'outerResolution': '2420x1080',
                },
            }),
            onRefresh: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
