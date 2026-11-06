import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/ios/ios_process_info.dart';
import 'package:any_deck/core/ios/ios_process_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/ios/controller/ios_processes_controller.dart';
import 'package:any_deck/features/ios/ios_processes_tab.dart';
import 'package:any_deck/features/ios/ios_syslog_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_process.dart';

class _Commands extends IosCommandService {
  final processes = <ControlledProcess>[];
  Completer<Process>? starting;
  @override
  Future<Process> startSyslog(String udid) async {
    final process = ControlledProcess();
    processes.add(process);
    return starting?.future ?? process;
  }
}

class _Service extends IosProcessService {
  _Service() : super(IosCommandService(), 'phone');
  int closes = 0, reads = 0;
  Completer<List<IosProcessInfo>>? pending;
  @override
  Future<List<IosProcessInfo>> read({bool refreshApps = false}) async {
    reads++;
    return pending?.future ?? [const IosProcessInfo(pid: 1, name: 'New')];
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

const _device = DiscoveredDevice(id: 'phone', status: 'device', isIos: true);
Widget _page(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// 使用模拟 CLI/Future 验证隐藏恢复、手动停止及迟到请求的资源释放。
void main() {
  testWidgets('iOS 日志隐藏时杀进程，返回恢复，手动停止后不自动重启', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final commands = _Commands();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [iosCommandServiceProvider.overrideWithValue(commands)],
        child: _page(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, active, _) =>
                IosSyslogTab(device: _device, isVisible: active),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(commands.processes.length, 1);
    commands.processes.first.output.add(utf8.encode('hello\n'));
    await tester.pump(const Duration(milliseconds: 110));
    await tester.pump();
    visible.value = false;
    await tester.pump();
    await tester.pump();
    expect(commands.processes.first.signals, isNotEmpty);
    visible.value = true;
    await tester.pump();
    await tester.pump();
    expect(commands.processes.length, 2);
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await tester.pump();
    visible.value = false;
    await tester.pump();
    visible.value = true;
    await tester.pump();
    await tester.pump();
    expect(commands.processes.length, 2);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS 日志启动尚未返回便隐藏时，迟到进程不得挂回', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final commands = _Commands()..starting = Completer<Process>();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [iosCommandServiceProvider.overrideWithValue(commands)],
        child: _page(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, active, _) =>
                IosSyslogTab(device: _device, isVisible: active),
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    visible.value = false;
    await tester.pump();
    final lateProcess = ControlledProcess();
    commands.starting!.complete(lateProcess);
    await tester.pump();
    await tester.pump();
    expect(lateProcess.signals, isNotEmpty);
    expect(find.byIcon(Icons.stop), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS 进程页在 IndexedStack 中隐藏也释放会话并丢弃旧请求', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final old = _Service()..pending = Completer<List<IosProcessInfo>>();
    final current = _Service();
    var sessions = 0;
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceOnlineProvider.overrideWith((ref, id) => true),
          iosProcessServiceProvider.overrideWith(
            (ref, id) => sessions++ == 0 ? old : current,
          ),
        ],
        child: _page(
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, active, _) => IndexedStack(
              index: active ? 0 : 1,
              children: [
                IosProcessesTab(device: _device, isVisible: active),
                const SizedBox(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    visible.value = false;
    await tester.pump();
    await tester.pump();
    expect(old.closes, greaterThan(0));
    old.pending!.complete([const IosProcessInfo(pid: 2, name: 'Old')]);
    await tester.pump(const Duration(seconds: 12));
    expect(old.reads, 1);
    visible.value = true;
    await tester.pump();
    await tester.pump();
    expect(current.reads, 1);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
