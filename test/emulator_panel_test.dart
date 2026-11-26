import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_emulator_config.dart';
import 'package:any_deck/core/emulator/android_emulator.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/emulator/emulator_process.dart';
import 'package:any_deck/core/emulator/emulator_running_provider.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/providers/modules/emulator_terminal_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/widgets/dashboard_table_header.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/search_field_expectations.dart';

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

/// 已启动进程失去 ADB transport 的测试状态。
class _AliveLaunch extends EmulatorLaunchNotifier {
  @override
  Map<String, EmulatorLaunchState> build() => {
    'Small_Phone': const EmulatorLaunchState(processAlive: true),
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

  testWidgets('Android 模拟器沿用 iOS 列表边距且六列随窗口缩放', (tester) async {
    const emulator = AndroidEmulator(
      name: 'Medium_Phone_API_37.0_with_a_long_display_name',
      resolution: '1080x2400',
      sdkVersion: '37.0',
      abi: 'arm64-v8a',
      memory: '2G',
      storage: '8G',
    );
    const iosSimulator = IosSimulator(
      udid: 'test-ios',
      name: 'Test iPhone',
      runtime: 'iOS 26',
      deviceTypeIdentifier: 'iPhone',
      state: 'Shutdown',
      isAvailable: true,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
          emulatorListProvider.overrideWith((ref) async => [emulator]),
          emulatorConnectionsProvider.overrideWith((ref) async => {}),
          iosSimulatorsProvider.overrideWith((ref) async => [iosSimulator]),
        ],
        child: _app(
          const Padding(
            padding: EdgeInsets.only(left: 180),
            child: EmulatorListPanel(isFullPage: true),
          ),
        ),
      ),
    );

    final headers = find.byType(DashboardSortableHeaderCell);
    final values = [
      emulator.displayName,
      emulator.resolutionLabel,
      emulator.sdkVersionLabel,
      emulator.abiLabel,
      emulator.memoryLabel,
      emulator.storageLabel,
    ];
    // 连续调整窗口，检查满宽列表、对称内边距及六列对齐。
    final previousWidths = List.filled(values.length, double.infinity);
    for (final width in [1580.0, 1100.0, 800.0, 700.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpAndSettle();
      expect(headers, findsNWidgets(values.length));
      final tableTop = tester.getRect(find.byType(Divider)).bottom;
      final list = tester.getRect(find.byType(ListView));
      final searchLeft = tester.getRect(find.byType(TextField)).left;
      final statusDot = tester.getRect(find.byTooltip('已关闭'));
      expect(list.top, closeTo(tableTop + 48, 0.01));
      expect(list.bottom, closeTo(800, 0.01));
      expect(list.left, closeTo(180, 0.01));
      expect(list.right, closeTo(width, 0.01));
      expect(searchLeft, closeTo(180 + 28, 0.01));
      expect(tester.getRect(headers.first).left, closeTo(searchLeft, 0.01));
      expect(tester.getRect(headers.last).right, closeTo(width - 28, 0.01));
      expect(
        tester.getRect(find.text('模拟器名称')).left,
        closeTo(searchLeft + 20, 0.01),
      );
      expect(statusDot.left, closeTo(searchLeft, 0.01));
      expect(statusDot.center.dy, closeTo(list.top + 28, 0.01));
      for (var i = 0; i < values.length; i++) {
        final header = tester.getRect(headers.at(i));
        expect(header.center.dy, closeTo(tableTop + 24, 0.01));
        expect(header.width, lessThan(previousWidths[i]));
        previousWidths[i] = header.width;
        final value = tester.getRect(find.text(values[i]));
        final title = tester.getRect(
          find.descendant(of: headers.at(i), matching: find.byType(Text)),
        );
        expect(value.width, greaterThan(0));
        expect(value.left, closeTo(title.left, 0.01));
        expect(value.right, lessThanOrEqualTo(header.right + 0.01));
        expect(value.center.dy, closeTo(list.top + 28, 0.01));
      }
      final details = find.byIcon(CupertinoIcons.info_circle);
      expect(details.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(details).right,
        lessThanOrEqualTo(tester.getRect(headers.first).right),
      );
      expect(tester.takeException(), isNull);
    }

    // 在同一页面切换到 iOS，核对名称列及表格边界。
    final androidList = tester.getRect(find.byType(ListView));
    final androidNameLeft = tester.getRect(find.text(values.first)).left;
    await tester.tap(find.text('iOS'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final iosList = tester.getRect(find.byType(ListView));
    expect(iosList.left, closeTo(androidList.left, 0.01));
    expect(iosList.right, closeTo(androidList.right, 0.01));
    expect(iosList.bottom, closeTo(androidList.bottom, 0.01));
    expect(
      iosList.top,
      closeTo(tester.getRect(find.byType(Divider)).bottom, 0.01),
    );
    expect(
      tester.getRect(find.text('模拟器名称')).left,
      closeTo(androidNameLeft, 0.01),
    );
    expect(
      tester.getRect(find.text(iosSimulator.name)).left,
      closeTo(androidNameLeft, 0.01),
    );
    expect(tester.takeException(), isNull);
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
      expectSearchFieldRadius(tester, find.byType(TextField), focused: false);
      expect(find.text('运行内存（MiB）'), findsOneWidget);
      expect(find.text('hw.ramSize'), findsOneWidget);
      expect(find.text('强制从指定快照启动'), findsOneWidget);
      expect(find.text('fastboot.forceChosenSnapshotBoot'), findsOneWidget);
      expect(find.text('其他配置项'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '运行内存');
      await tester.pumpAndSettle();
      expectSearchFieldRadius(tester, find.byType(TextField), focused: true);
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
    expectSearchFieldRadius(tester, find.byType(TextField), focused: false);
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
          runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
          emulatorListProvider.overrideWith((ref) async => [_emulator]),
          emulatorConnectionsProvider.overrideWith((ref) async => {}),
          emulatorLaunchProvider.overrideWith(_FailedLaunch.new),
        ],
        child: _app(const EmulatorListPanel(isFullPage: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('在独立窗口显示'), findsNothing);
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
  testWidgets(
    'unauthorized emulator has connection guidance and responsive toolbar',
    (tester) async {
      tester.view.physicalSize = const Size(760, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
            emulatorListProvider.overrideWith((ref) async => [_emulator]),
            emulatorConnectionsProvider.overrideWith(
              (ref) async => {
                'Small_Phone': const DiscoveredDevice(
                  id: 'emulator-5554',
                  status: 'unauthorized',
                ),
              },
            ),
            emulatorLaunchProvider.overrideWith(_FailedLaunch.new),
          ],
          child: _app(
            const EmulatorListPanel(isFullPage: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expectSearchFieldRadius(tester, find.byType(TextField), focused: false);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.link_off), findsOneWidget);
      expect(find.textContaining('ADB 未授权'), findsOneWidget);
      expect(find.text('停止'), findsOneWidget);
      await tester.tap(find.text('Small Phone'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      expect(find.text('冷启动（不加载快照）'), findsOneWidget);
      expect(find.text('清空模拟器数据'), findsOneWidget);
      await tester.tapAt(const Offset(10, 600));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no matches');
      await tester.pumpAndSettle();
      expectSearchFieldRadius(tester, find.byType(TextField), focused: true);
      expect(find.text('Small Phone'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('live process without ADB transport is not shown as stopped', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runningEmulatorCountsProvider.overrideWithValue(noRunningEmulators),
          emulatorListProvider.overrideWith((ref) async => [_emulator]),
          emulatorConnectionsProvider.overrideWith((ref) async => {}),
          emulatorLaunchProvider.overrideWith(_AliveLaunch.new),
        ],
        child: _app(
          const EmulatorListPanel(isFullPage: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.link_off), findsOneWidget);
    expect(find.byTooltip('已关闭'), findsNothing);
    expect(find.textContaining('模拟器进程仍在运行'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
