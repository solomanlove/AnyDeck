import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/process/process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/web_debug/webpage_target.dart';
import 'package:any_deck/features/processes/processes_tab.dart';
import 'package:any_deck/features/webpages/webpages_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Packages extends PackagesNotifier {
  _Packages() : super('phone');
  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncData([]);
}

/// 让查询跨越多个定时周期，验证静默刷新、重连及隐藏生命周期。
void main() {
  for (final webpage in [false, true]) {
    testWidgets('${webpage ? '网页' : '进程'}静默查询超过多个周期也只有一次在途，隐藏后停止轮询', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final visible = ValueNotifier(true);
      final online = ValueNotifier(true);
      addTearDown(online.dispose);
      addTearDown(visible.dispose);
      final processes = Completer<List<AdbProcess>>();
      final targets = Completer<List<WebpageTarget>>();
      var queries = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceOnlineProvider.overrideWith((ref, id) => true),
            packagesProvider('phone').overrideWith(_Packages.new),
            processesProvider.overrideWith((ref, id) async {
              queries++;
              return queries == 1 ? [] : processes.future;
            }),
            webTargetsProvider.overrideWith((ref, id) async {
              queries++;
              return queries == 1 ? [] : targets.future;
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (_, active, _) => ValueListenableBuilder<bool>(
                  valueListenable: online,
                  builder: (_, connected, _) {
                    final device = DiscoveredDevice(
                      id: 'phone',
                      status: connected ? 'device' : 'offline',
                    );
                    return webpage
                        ? WebpagesTab(device: device, isVisible: active)
                        : ProcessesTab(device: device, isVisible: active);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(queries, 1);
      final interval = Duration(seconds: webpage ? 5 : 3);
      await tester.pump(interval);
      await tester.pump();
      expect(queries, 2);
      await tester.pump(interval * 3);
      expect(queries, 2);
      if (!webpage) {
        // 断线不能提前释放仍在执行的查询锁；重连后等待原请求结束。
        online.value = false;
        await tester.pump();
        online.value = true;
        await tester.pump();
        await tester.pump(interval);
        expect(queries, 2);
      }
      if (webpage) {
        targets.complete([]);
      } else {
        processes.complete([]);
      }
      await tester.pump();
      visible.value = false;
      await tester.pump();
      await tester.pump(interval * 3);
      expect(queries, 2);
      visible.value = true;
      await tester.pump();
      await tester.pump(interval);
      await tester.pump();
      expect(queries, 3);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
