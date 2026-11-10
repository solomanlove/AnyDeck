import 'dart:async';
import 'dart:io';

import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/host_recording_backend.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_record_runner.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/host_recording_fakes.dart';

void main() {
  late Directory directory;
  late RecordingTestHost host;
  late ProviderContainer container;
  late List<ScreenRecordPhase> phases;
  late Provider<ScreenshotRecordRunner> runnerProvider;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'anydeck-screenshot-record-',
    );
    host = RecordingTestHost();
    phases = [];
    runnerProvider = Provider((ref) {
      final runner = ScreenshotRecordRunner(
        deviceId: 'fixture',
        ref: ref,
        onPhaseChanged: phases.add,
        onDurationChanged: (_) {},
      );
      ref.onDispose(runner.dispose);
      return runner;
    });
    container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(
          () => RecordingTestSettings(directory.path, true),
        ),
        adbServiceProvider.overrideWithValue(RecordingTestAdb()),
        deviceRegistryProvider.overrideWith(RecordingTestRegistry.new),
        hostRecordingFactoryProvider.overrideWithValue((_, _) => host),
      ],
    );
  });
  tearDown(() {
    container.dispose();
    directory.deleteSync(recursive: true);
  });

  Future<BuildContext> contextFor(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('截图页面等待内置录制收尾后才提示保存成功', (tester) async {
    final context = await contextFor(tester);
    final runner = container.read(runnerProvider);
    await tester.runAsync(() => runner.startRecording(context: context));
    expect(phases, [ScreenRecordPhase.starting, ScreenRecordPhase.recording]);
    await tester.runAsync(() => runner.stopRecording(context: context));
    await tester.pump();
    expect(
      phases,
      containsAllInOrder([
        ScreenRecordPhase.stopping,
        ScreenRecordPhase.saving,
        ScreenRecordPhase.idle,
      ]),
    );
    expect(host.stops, 1);
    expect(find.textContaining('screenrecord_fixture_'), findsOneWidget);
  });

  testWidgets('MP4 收尾失败提示错误，不显示成功路径', (tester) async {
    host.failStop = true;
    final context = await contextFor(tester);
    final runner = container.read(runnerProvider);
    await tester.runAsync(() => runner.startRecording(context: context));
    await tester.runAsync(() => runner.stopRecording(context: context));
    await tester.pump();
    expect(phases.last, ScreenRecordPhase.idle);
    expect(find.textContaining('MP4 finalize failed'), findsOneWidget);
    expect(find.textContaining('screenrecord_fixture_'), findsNothing);
  });

  testWidgets('启动中关闭页面会取消会话，迟到完成不回调 UI', (tester) async {
    final context = await contextFor(tester);
    final runner = container.read(runnerProvider);
    await tester.runAsync(() async {
      host.starting = Completer<void>();
      final starting = runner.startRecording(context: context);
      await host.entered.future.timeout(const Duration(seconds: 3));
      runner.dispose();
      final previous = List<ScreenRecordPhase>.of(phases);
      host.starting!.complete();
      await starting;
      expect(phases, previous);
      expect(host.cancellations, 1);
    });
  });
}
