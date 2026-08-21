import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/window/mirror/mirror_device_info_overlay.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('投屏设备信息卡展示设备与存储摘要', (tester) async {
    final overview = DeviceOverview.fromJson({
      'name': '华为 P20',
      'brand': 'HUAWEI',
      'model': 'EML-L29C',
      'androidVersion': 'Android 8.1.0',
      'memory': '6.00G',
      'storage': '35.00G / 128.00G',
      'rawResolution': '1080x2240',
      'refreshRate': '60 Hz',
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: MirrorDeviceInfoCard(
            overview: overview,
            fallbackName: '备用名称',
          ),
        ),
      ),
    );

    expect(find.text('华为 P20'), findsOneWidget);
    expect(find.text('HUAWEI (EML-L29C)'), findsOneWidget);
    expect(find.text('1080 × 2240 (60Hz)'), findsOneWidget);
    expect(find.text('内存：6.00G'), findsOneWidget);
    expect(find.text('Android 8.1.0'), findsOneWidget);
    expect(find.text('存储：35.00G / 128.00G'), findsOneWidget);
  });
}
