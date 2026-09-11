import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单独验证概览内容，避免启动设备查询与无关 Tab 的原生插件。
void main() {
  for (final width in [1000.0, 600.0]) {
    for (final locale in ['zh', 'en']) {
      testWidgets('概览容量布局 $width $locale', (tester) async {
        tester.view.physicalSize = Size(width, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: Locale(locale),
              theme: ThemeData(
                brightness: locale == 'zh' ? Brightness.light : Brightness.dark,
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
                  device: const AdbDevice(id: 'test', status: 'device'),
                  overview: DeviceOverview.fromJson({
                    'name': 'Redmi K40',
                    'brand': 'Redmi',
                    'androidVersion': 'Android 13 (API 33)',
                    'customOs': 'HyperOS OS1.0',
                    'memory': '11.24G',
                    'memoryUsed': '6.00G',
                    'storage': '180.74G / 225.43G',
                  }),
                  onRefresh: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final memory = find.text('6.00G / 11.24G');
        final storage = find.text('180.74G / 225.43G');
        expect(memory, findsOneWidget);
        expect(storage, findsOneWidget);
        final memoryPosition = tester.getTopLeft(memory);
        final storagePosition = tester.getTopLeft(storage);
        if (width >= 720) {
          expect(memoryPosition.dx, lessThan(storagePosition.dx));
          expect(memoryPosition.dy, closeTo(storagePosition.dy, 1));
        } else {
          expect(memoryPosition.dy, lessThan(storagePosition.dy));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
