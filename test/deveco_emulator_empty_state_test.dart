import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_providers.dart';
import 'package:any_deck/core/emulator/harmony/deveco_emulator_service.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/providers/modules/service_providers.dart';
import 'package:any_deck/features/devices/widgets/deveco_emulators_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟外部应用探测和唤起，用请求计数验证 UI 触发时机。
class _StudioService extends DevEcoEmulatorService {
  _StudioService({required this.detect, super.platform = TargetPlatform.macOS});

  final Future<String?> Function() detect;
  final openResult = Completer<bool>();
  final openedPaths = <String?>[];
  var detectionCount = 0;

  @override
  Future<String?> findDevEcoStudio() {
    detectionCount++;
    return detect();
  }

  @override
  Future<bool> openDevEcoStudio({String? appPath}) {
    openedPaths.add(appPath);
    return openResult.future;
  }
}

class _BrowserLauncher extends HostPlatformService {
  final openedUris = <Uri>[];

  @override
  Future<bool> openWebUri(Uri uri) async {
    openedUris.add(uri);
    return true;
  }
}

/// 通过实际 HarmonyOS 标签内容测试空态，隔离文件扫描与系统启动。
Future<void> _pumpView(
  WidgetTester tester, {
  required _StudioService service,
  required _BrowserLauncher browser,
  required Future<List<DevEcoEmulator>> Function() scan,
  String language = 'zh',
  Brightness brightness = Brightness.light,
  Size viewport = const Size(320, 450),
}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewport;
  addTearDown(tester.view.reset);
  addTearDown(AppToast.dismiss);
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        devecoEmulatorServiceProvider.overrideWithValue(service),
        devecoEmulatorsProvider.overrideWith((ref) => scan()),
        hostPlatformServiceProvider.overrideWithValue(browser),
      ],
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildAppTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: const Scaffold(body: DevecoEmulatorsView()),
      ),
    ),
  );
}

void main() {
  for (final (language, brightness, title, download) in [
    ('zh', Brightness.light, '未检测到 DevEco Studio', '下载 DevEco Studio'),
    (
      'en',
      Brightness.dark,
      'DevEco Studio not detected',
      'Download DevEco Studio',
    ),
  ]) {
    testWidgets('无 DevEco Studio 时提供官方下载入口 $language', (tester) async {
      final scan = Completer<List<DevEcoEmulator>>();
      final detection = Completer<String?>();
      final service = _StudioService(detect: () => detection.future);
      final browser = _BrowserLauncher();
      await _pumpView(
        tester,
        service: service,
        browser: browser,
        scan: () => scan.future,
        language: language,
        brightness: brightness,
      );

      expect(service.detectionCount, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      scan.complete([]);
      await tester.pump();
      expect(service.detectionCount, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      detection.complete(null);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final action = find.widgetWithText(FilledButton, download);
      expect(action, findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(browser.openedUris, isEmpty);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(browser.openedUris, [
        Uri.parse(ConnectionEnvironmentService.devecoStudioDownloadUrl),
      ]);
      expect(service.openedPaths, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('使用已检测的应用路径，打开失败后重新探测', (tester) async {
    String? detectedApp = '/Applications/Developer Tools/DevEco Studio.app';
    final service = _StudioService(detect: () async => detectedApp);
    final browser = _BrowserLauncher();
    await _pumpView(
      tester,
      service: service,
      browser: browser,
      scan: () async => [],
    );
    await tester.pumpAndSettle();

    expect(find.text('未发现本地 HarmonyOS 模拟器'), findsOneWidget);
    expect(find.textContaining('Tools → Device Manager'), findsOneWidget);
    final action = find.widgetWithText(FilledButton, '打开 DevEco Studio');
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pump();
    expect(tester.widget<FilledButton>(action).onPressed, isNull);
    expect(service.openedPaths, [detectedApp]);

    detectedApp = null;
    service.openResult.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('无法打开 DevEco Studio，正在重新检测安装状态。'), findsOneWidget);
    expect(service.detectionCount, 2);
    expect(action, findsNothing);
    expect(
      find.widgetWithText(FilledButton, '下载 DevEco Studio'),
      findsOneWidget,
    );
    expect(browser.openedUris, isEmpty);
  });

  testWidgets('其他平台显示通用安装引导', (tester) async {
    final service = _StudioService(
      platform: TargetPlatform.windows,
      detect: () async => null,
    );
    await _pumpView(
      tester,
      service: service,
      browser: _BrowserLauncher(),
      scan: () async => [],
    );
    await tester.pumpAndSettle();
    expect(service.detectionCount, 0);
    expect(find.text('未发现本地 HarmonyOS 模拟器'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, '下载 DevEco Studio'),
      findsOneWidget,
    );
  });

  testWidgets('有本地模拟器及搜索无匹配时跳过应用探测', (tester) async {
    final service = _StudioService(detect: () async => null);
    await _pumpView(
      tester,
      service: service,
      browser: _BrowserLauncher(),
      viewport: const Size(620, 700),
      scan: () async => [
        const DevEcoEmulator(
          name: 'Test Phone',
          apiVersion: 'API 12',
          deviceType: 'Phone',
          state: 'Stopped',
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Test Phone'), findsOneWidget);
    final search = find.byType(TextField);
    await tester.enterText(search, 'no matches');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配 "no matches" 的模拟器'), findsOneWidget);
    expect(search, findsOneWidget);
    expect(service.detectionCount, 0);
  });
}
