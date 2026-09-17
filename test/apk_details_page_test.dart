import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/apk/apk_window_client.dart';
import 'package:any_deck/core/apk/local_apk_info.dart';
import 'package:any_deck/features/apk/apk_details_page.dart';
import 'package:any_deck/features/apk/widgets/apk_detail_list.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('离线详情可用，安装禁用，SDK 标签准确；dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(1120, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const path = '/tmp/example.apk';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localApkProvider(path).overrideWith(
              (ref) async => LocalApkInfo({
                'packageName': 'example.app',
                'label': 'Example',
                'versionName': '1.0',
                'versionCode': '1',
                'minSdk': '23',
                'targetSdk': '34',
                'size': 1234,
                'permissions': [
                  {'name': 'android.permission.CAMERA'},
                ],
              }),
            ),
            apkDevicesProvider(
              'main',
            ).overrideWith((ref) => Stream.value({'devices': <dynamic>[]})),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: const ApkDetailsPage(path: path, mainWindowId: 'main'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Target SDK'), findsOneWidget);
      expect(find.text('Not provided'), findsOneWidget);
      final install = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Install / Replace'),
      );
      expect(install.onPressed, isNull);
      expect(tester.takeException(), isNull);
      // 最小窗口尺寸下也不发生布局溢出。
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ApkDetailList 支持解析展示 Activity 图标、真实标题与类名', (tester) async {
    const testIconBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    final rows = [
      {
        'name': 'de.syss.MifareClassicTool.Activities.MainMenu',
        'label': '主菜单',
        'rawLabel': '@string/title_activity_main',
        'icon': testIconBase64,
        'rawIcon': '@drawable/map_keys_to_sector',
        'exported': 'true',
      },
      {
        'name': 'de.syss.MifareClassicTool.Activities.DumpEditor',
        'exported': 'false',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: ApkDetailList(
            rows: rows,
            showComponentIcon: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 验证真实标题作为主标题展示
    expect(find.text('主菜单'), findsOneWidget);
    // 验证类名作为副标题展示
    expect(find.textContaining('de.syss.MifareClassicTool.Activities.MainMenu'), findsOneWidget);
    // 验证原始引用格式展示
    expect(find.textContaining('label: 主菜单 (@string/title_activity_main)'), findsOneWidget);
    expect(find.textContaining('icon: @drawable/map_keys_to_sector'), findsOneWidget);
    // 验证未泄露 Base64 字符串
    expect(find.textContaining(testIconBase64), findsNothing);
    // 验证未声明 label 的 Activity 以类名为标题
    expect(find.text('de.syss.MifareClassicTool.Activities.DumpEditor'), findsOneWidget);
    // 验证图标正常渲染（自定义图片与占位图标）
    expect(find.byType(Image), findsOneWidget);
  });
}
