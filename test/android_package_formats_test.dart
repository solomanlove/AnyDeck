import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/widget/app_detail_layout.dart';
import 'package:any_deck/core/apk/android_package_format.dart';
import 'package:any_deck/core/apk/apk_file_open_queue.dart';
import 'package:any_deck/core/apk/apk_install_controller.dart';
import 'package:any_deck/core/apk/apk_window_client.dart';
import 'package:any_deck/core/apk/local_apk_info.dart';
import 'package:any_deck/core/apk/local_apk_service.dart';
import 'package:any_deck/features/apk/apk_details_page.dart';
import 'package:any_deck/features/apk/widgets/apk_install_bar.dart';

void main() {
  test('格式识别区分扩展名与普通文件名', () {
    for (final format in AndroidPackageFormat.values) {
      expect(AndroidPackageFormat.fromPath('/tmp/中文.${format.label}'), format);
    }
    expect(AndroidPackageFormat.fromPath('/tmp/apk'), isNull);
    expect(AndroidPackageFormat.fromPath('/tmp/file.apks.zip'), isNull);
    expect(AndroidPackageFormat.fromPath('/tmp/folder.apk/file.txt'), isNull);
  });
  test('冷启动文件队列接收新格式并过滤其他文件', () async {
    final ready = Completer<void>();
    final opened = <String>[];
    final queue = ApkFileOpenQueue(
      ready: ready.future,
      openDocument: (path) async => opened.add(path),
      onError: (e) => fail('$e'),
    );
    queue.add([
      '/tmp/中文.APks',
      '/tmp/app.aab',
      '/tmp/app.XAPK',
      '/tmp/readme.txt',
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(opened, isEmpty);
    ready.complete();
    await queue.idle;
    expect(opened, ['/tmp/中文.APks', '/tmp/app.aab', '/tmp/app.XAPK']);
  });
  for (final format in ['APKS', 'AAB', 'XAPK']) {
    test('$format 解析入口可用，并禁止当成普通 APK 安装', () async {
      final dir = await Directory.systemTemp.createTemp(
        'anydeck-container-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/中文 app.$format');
      await file.writeAsString(
        '{"packageName":"example.app","label":"AnyDeck"}',
      );
      final service = LocalApkService(executable: '/bin/cat');
      addTearDown(service.dispose);
      final info = await service.inspect(file.path);
      expect(info.format, format);
      expect(info.installable, isFalse);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(apkInstallProvider('no-rpc').notifier)
          .install(file.path, 'device', info);
      expect(container.read(apkInstallProvider('no-rpc')).error, isNull);
      expect(
        container.read(apkInstallProvider('no-rpc')).installedSerial,
        isNull,
      );
    });
    for (final dark in [false, true]) {
      testWidgets('$format 离线分析展示分包或模块，不查询设备；dark=$dark', (tester) async {
        tester.view.physicalSize = const Size(1120, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final isBundle = format == 'AAB';
        final key = isBundle ? 'modules' : 'archiveEntries';
        final path = '/tmp/example.${format.toLowerCase()}';
        var deviceQueries = 0;
        final english = dark;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              localApkProvider(path).overrideWith(
                (ref) async => LocalApkInfo({
                  'format': format,
                  'packageName': 'example.app',
                  'label': 'AnyDeck',
                  'versionName': '1.0',
                  'versionCode': '1',
                  'minSdk': '23',
                  'targetSdk': '35',
                  key: [
                    {
                      'name': isBundle ? 'base' : 'splits/base-master.apk',
                      'size': 42,
                    },
                  ],
                }),
              ),
              apkDevicesProvider('main').overrideWith((ref) {
                deviceQueries++;
                return Stream.value({'devices': []});
              }),
            ],
            child: MaterialApp(
              locale: Locale(english ? 'en' : 'zh'),
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
              home: ApkDetailsPage(path: path, mainWindowId: 'main'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final view = tester.widget<AppDetailView>(find.byType(AppDetailView));
        expect(
          view.data.tabs.any((tab) => tab.id == key && tab.count == 1),
          isTrue,
        );
        expect(find.byType(ApkInstallBar), findsNothing);
        expect(
          find.widgetWithText(FilledButton, 'Install / Replace'),
          findsNothing,
        );
        expect(deviceQueries, 0);
        final tabTitle = view.data.tabs
            .firstWhere((tab) => tab.id == key)
            .displayTitle;
        await tester.tap(find.text(tabTitle));
        await tester.pumpAndSettle();
        expect(
          find.text(isBundle ? 'base' : 'splits/base-master.apk'),
          findsOneWidget,
        );
        tester.view.physicalSize = const Size(900, 600);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  test('解析完成后清理 helper 工作区', () async {
    final dir = await Directory.systemTemp.createTemp(
      'anydeck-parser-cleanup-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final parser = File('${dir.path}/parser');
    await parser.writeAsString(
      '#!/bin/sh\nprintf \'{"packageName":"example.app","workspace":"%s"}\' "\$ANYDECK_APK_WORK_DIR"\n',
    );
    await Process.run('/bin/chmod', ['+x', parser.path]);
    final file = File('${dir.path}/app.apks');
    await file.writeAsString('fixture');
    final service = LocalApkService(executable: parser.path);
    addTearDown(service.dispose);
    final info = await service.inspect(file.path);
    expect(info.text('workspace'), isNotEmpty);
    expect(await Directory(info.text('workspace')).exists(), isFalse);
  });
}
