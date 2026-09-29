import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_emulator_config.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/emulator/emulator_process.dart';
import 'package:any_deck/core/providers/modules/emulator_terminal_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定失败状态避免测试触发真实 emulator 或 ADB 进程。
class _FailedLaunch extends EmulatorLaunchNotifier {
  @override
  Map<String, EmulatorLaunchState> build() => {
    'Small_Phone': const EmulatorLaunchState(
      errorKey: 'emulatorLaunchExited',
      exitCode: 1,
      details:
          'Missing system image android-35/google_apis_playstore/arm64-v8a.',
    ),
  };
}

const _emulator = AndroidEmulator(
  name: 'Small_Phone',
  config: {
    'hw.ramSize': '1024',
    'fastboot.forceChosenSnapshotBoot': 'no',
    'vendor.unknown': 'custom',
  },
);

Widget _app(Widget child, {String language = 'zh', bool dark = false}) {
  return MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: dark ? ThemeData.dark() : ThemeData.light(),
    home: Scaffold(body: child),
  );
}

void main() {
  test('configuration translations have matching Chinese and English keys', () {
    expect(emulatorConfigZh.keys.toSet(), emulatorConfigEn.keys.toSet());
  });

  testWidgets(
    'configuration shows translated label and raw key, supports Chinese search',
    (tester) async {
      await tester.pumpWidget(
        _app(
          EmulatorFullConfigDialog(
            emulatorName: 'Small Phone',
            config: _emulator.config,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('运行内存（MiB）'), findsOneWidget);
      expect(find.text('hw.ramSize'), findsOneWidget);
      expect(find.text('强制从指定快照启动'), findsOneWidget);
      expect(find.text('fastboot.forceChosenSnapshotBoot'), findsOneWidget);
      expect(find.text('其他配置项'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '运行内存');
      await tester.pumpAndSettle();
      expect(find.text('hw.ramSize'), findsOneWidget);
      expect(find.text('vendor.unknown'), findsNothing);
      await tester.enterText(find.byType(TextField), '1024');
      await tester.pumpAndSettle();
      expect(find.text('hw.ramSize'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fastboot.');
      await tester.pumpAndSettle();
      expect(find.text('fastboot.forceChosenSnapshotBoot'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('English dark configuration retains original keys', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EmulatorFullConfigDialog(
          emulatorName: 'Small Phone',
          config: _emulator.config,
        ),
        language: 'en',
        dark: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RAM (MiB)'), findsOneWidget);
    expect(find.text('hw.ramSize'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed row exposes error dialog and explicit details action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          emulatorListProvider.overrideWith((ref) async => [_emulator]),
          runningEmulatorsProvider.overrideWith((ref) async => {}),
          emulatorLaunchProvider.overrideWith(_FailedLaunch.new),
        ],
        child: _app(const EmulatorListPanel(isStandalone: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.info_circle), findsOneWidget);
    expect(find.textContaining('Missing system image'), findsOneWidget);
    await tester.tap(find.byTooltip('查看启动错误'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('复制错误详情'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.info_circle));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byType(EmulatorFullConfigDialog), findsOneWidget);
    expect(find.text('运行内存（MiB）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
