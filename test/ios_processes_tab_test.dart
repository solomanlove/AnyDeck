import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/ios/ios_app_info.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/ios/controller/ios_processes_controller.dart';
import 'package:any_deck/core/ios/ios_process_info.dart';
import 'package:any_deck/features/ios/ios_processes_tab.dart';
import 'package:any_deck/features/ios/widgets/ios_process_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 只通过 Future 桩验证页面，禁止启动真实进程。
class _Service extends IosProcessService {
  _Service(String udid, this.pending) : super(IosCommandService(), udid);
  final Completer<List<IosProcessInfo>> pending;
  @override
  Future<List<IosProcessInfo>> read({bool refreshApps = false}) =>
      pending.future;
}

Widget _page(
  Widget child, {
  String language = 'en',
  Brightness brightness = Brightness.light,
}) {
  return MaterialApp(
    locale: Locale(language),
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(brightness: brightness),
    home: Scaffold(body: child),
  );
}

void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('$language 窄屏明暗主题展示扩展及宿主信息，无布局溢出', (tester) async {
      tester.view.physicalSize = const Size(420, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          _page(
            IosProcessTile(
              process: IosProcessInfo(
                pid: 286,
                name: 'NotificationService',
                executablePath:
                    '/private/var/containers/Bundle/Application/UUID/Netdisk.app/PlugIns/NotificationService.appex/NotificationService',
                startedAt: DateTime(2026, 10, 5, 22, 36, 49),
                bundleId: 'com.example.disk.notification',
                app: const IosAppInfo(
                  bundleId: 'com.example.disk',
                  name: '网盘',
                  version: '13.32.2',
                ),
              ),
            ),
            language: language,
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('网盘 · NotificationService'), findsOneWidget);
        expect(
          find.text(
            '${language == 'zh' ? '宿主' : 'Host'} Bundle ID: com.example.disk',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Bundle ID: com.example.disk.notification'),
          findsOneWidget,
        );
        expect(find.textContaining('13.32.2'), findsOneWidget);
        expect(find.textContaining('2026-10-05 22:36:49'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('没有应用信息时仍显示进程名和 PID，不伪造 Bundle ID', (tester) async {
    await tester.pumpWidget(
      _page(
        const IosProcessTile(process: IosProcessInfo(pid: 42, name: 'Runner')),
      ),
    );
    expect(find.text('Runner'), findsOneWidget);
    expect(find.text('PID: 42'), findsOneWidget);
    expect(find.textContaining('Bundle ID'), findsNothing);
  });

  testWidgets('设备切换后旧请求完成不得覆盖当前进程信息', (tester) async {
    final pending = {
      'a': Completer<List<IosProcessInfo>>(),
      'b': Completer<List<IosProcessInfo>>(),
    };
    Widget page(String id) => ProviderScope(
      overrides: [
        deviceOnlineProvider.overrideWith((ref, id) => true),
        iosProcessServiceProvider.overrideWith(
          (ref, id) => _Service(id, pending[id]!),
        ),
      ],
      child: _page(
        IosProcessesTab(
          device: AdbDevice(id: id, status: 'device', isIos: true),
        ),
      ),
    );
    await tester.pumpWidget(page('a'));
    await tester.pumpWidget(page('b'));
    pending['b']!.complete([const IosProcessInfo(pid: 2, name: 'New')]);
    await tester.pumpAndSettle();
    pending['a']!.complete([const IosProcessInfo(pid: 1, name: 'Old')]);
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
