import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_service.dart';
import 'package:any_deck/features/devices/widgets/ios_simulators_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 捕获列表入口触发的操作，并控制打开窗口的完成时机。
class _SimulatorService extends IosSimulatorService {
  final opened = <String>[];
  final booted = <String>[];
  final windowResult = Completer<bool>();
  var appOpenCount = 0;

  @override
  Future<bool> bootSimulator(String udid) async {
    booted.add(udid);
    return true;
  }

  @override
  Future<bool> showSimulatorWindow(String udid) {
    opened.add(udid);
    return windowResult.future;
  }

  @override
  Future<bool> openSimulatorApp() async {
    appOpenCount++;
    return true;
  }
}

const _running = IosSimulator(
  udid: 'running',
  name: 'iPhone 17',
  runtime: 'iOS 27.2',
  deviceTypeIdentifier: 'iPhone',
  state: 'Booted',
  isAvailable: true,
);

const _stopped = IosSimulator(
  udid: 'stopped',
  name: 'iPhone 17 Pro',
  runtime: 'iOS 27.2',
  deviceTypeIdentifier: 'iPhone',
  state: 'Shutdown',
  isAvailable: true,
);

Future<void> _pumpList(
  WidgetTester tester,
  _SimulatorService service,
  Locale locale,
) async {
  await tester.binding.setSurfaceSize(const Size(680, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        iosSimulatorServiceProvider.overrideWithValue(service),
        iosSimulatorsProvider.overrideWith((ref) async => [_running, _stopped]),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: const Scaffold(body: IosSimulatorsView()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _primaryButton(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

void main() {
  testWidgets('已运行设备显示窗口，打开中禁用入口，失败后可重试', (tester) async {
    final service = _SimulatorService();
    await _pumpList(tester, service, const Locale('zh'));
    await tester.tap(find.text(_running.name));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();

    final showWindow = _primaryButton('显示窗口');
    await tester.tap(showWindow);
    await tester.pump();
    expect(service.opened, [_running.udid]);
    expect(service.booted, isEmpty);
    expect(tester.widget<FilledButton>(showWindow).onPressed, isNull);

    service.windowResult.complete(false);
    await tester.pump();
    expect(find.text('无法打开 iOS 模拟器窗口，请检查 Xcode。'), findsOneWidget);
    expect(tester.widget<FilledButton>(showWindow).onPressed, isNotNull);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('双击已运行设备唤出窗口，工具栏仍可打开模拟器应用或启动关机设备', (tester) async {
    final service = _SimulatorService()..windowResult.complete(true);
    await _pumpList(tester, service, const Locale('en'));
    await tester.tap(find.text(_running.name));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    expect(_primaryButton('Show Window'), findsOneWidget);

    await tester.tap(find.text(_running.name));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text(_running.name));
    await tester.pumpAndSettle();
    expect(service.opened, [_running.udid]);
    expect(service.booted, isEmpty);

    await tester.tap(find.byTooltip('Open iOS Simulator App'));
    await tester.pumpAndSettle();
    expect(service.appOpenCount, 1);

    await tester.tap(find.text(_stopped.name));
    await tester.pump(kDoubleTapTimeout);
    await tester.pumpAndSettle();
    await tester.tap(_primaryButton('Start'));
    await tester.pumpAndSettle();
    expect(service.booted, [_stopped.udid]);
    expect(find.text('iOS simulator started'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
