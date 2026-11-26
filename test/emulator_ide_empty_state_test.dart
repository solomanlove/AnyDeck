import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/core/emulator/emulator_ide_providers.dart';
import 'package:any_deck/core/emulator/emulator_ide_service.dart';
import 'package:any_deck/core/emulator/ios/ios_simulator_providers.dart';
import 'package:any_deck/core/process/host_platform_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用夹具捕获真实管理页发起的探测、下载和打开操作。
class _IdeService extends EmulatorIdeService {
  _IdeService({super.platform = TargetPlatform.macOS});

  var studioChecks = 0;
  var xcodeChecks = 0;
  String? detectedPath;
  final opened = <String>[];

  @override
  Future<String?> findAndroidStudio() async {
    studioChecks++;
    return detectedPath;
  }

  @override
  Future<String?> findXcode() async {
    xcodeChecks++;
    return detectedPath;
  }

  @override
  Future<bool> open(String path) async {
    opened.add(path);
    detectedPath = null;
    return false;
  }
}

class _Browser extends HostPlatformService {
  final visited = <Uri>[];

  @override
  Future<bool> openWebUri(Uri uri) async {
    visited.add(uri);
    return true;
  }
}

Future<ProviderContainer> _showManager(
  WidgetTester tester, {
  required bool showIos,
  required _IdeService ide,
  required _Browser browser,
  required Future<void> scan,
  String language = 'zh',
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(620, 700);
  addTearDown(tester.view.reset);
  addTearDown(AppToast.dismiss);

  final container = ProviderContainer(
    overrides: [
      emulatorIdeServiceProvider.overrideWithValue(ide),
      hostPlatformServiceProvider.overrideWithValue(browser),
      runningEmulatorCountsProvider.overrideWithValue((
        android: 0,
        harmony: 0,
        ios: showIos ? 1 : 0,
      )),
      emulatorListProvider.overrideWith((ref) async {
        await scan;
        return [];
      }),
      emulatorConnectionsProvider.overrideWith((ref) async => {}),
      iosSimulatorsProvider.overrideWith((ref) async {
        await scan;
        return [];
      }),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          ...GlobalMaterialLocalizations.delegates,
        ],
        theme: buildAppTheme(
          language == 'zh' ? Brightness.light : Brightness.dark,
        ),
        home: const Scaffold(body: EmulatorListPanel(isFullPage: true)),
      ),
    ),
  );
  return container;
}

void main() {
  for (final showIos in [false, true]) {
    final name = showIos ? 'Xcode' : 'Android Studio';
    testWidgets('$name 空态下载、创建指引和打开失败重检', (tester) async {
      final ide = _IdeService();
      final browser = _Browser();
      final scan = Completer<void>();
      final container = await _showManager(
        tester,
        showIos: showIos,
        ide: ide,
        browser: browser,
        scan: scan.future,
        language: showIos ? 'en' : 'zh',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(ide.studioChecks + ide.xcodeChecks, 0);

      scan.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text(showIos ? '$name not detected' : '未检测到 $name'),
        findsOneWidget,
      );
      final download = find.widgetWithText(
        FilledButton,
        showIos ? 'Download $name' : '下载 $name',
      );
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(
        browser.visited.single.toString(),
        showIos
            ? 'https://apps.apple.com/us/app/xcode/id497799835'
            : 'https://developer.android.com/studio',
      );

      final provider = showIos
          ? xcodeAppPathProvider
          : androidStudioAppPathProvider;
      final path = '/Applications/Custom IDEs/$name.app';
      ide.detectedPath = path;
      container.invalidate(provider);
      await tester.pumpAndSettle();
      expect(
        find.textContaining(showIos ? 'Device Hub' : 'Create Virtual Device'),
        findsOneWidget,
      );
      expect(download, findsNothing);
      final open = find.widgetWithText(
        FilledButton,
        showIos ? 'Open $name' : '打开 $name',
      );
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(ide.opened, [path]);
      expect(find.byKey(const Key('appToast')), findsOneWidget);
      expect(download, findsOneWidget);
      expect(ide.studioChecks, showIos ? 0 : 3);
      expect(ide.xcodeChecks, showIos ? 3 : 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('非 macOS 的 iOS 空态说明平台要求', (tester) async {
    final ide = _IdeService(platform: TargetPlatform.windows);
    await _showManager(
      tester,
      showIos: true,
      ide: ide,
      browser: _Browser(),
      scan: Future<void>.value(),
    );
    await tester.pumpAndSettle();
    expect(find.text('iOS 模拟器需要 macOS'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(ide.xcodeChecks, 0);
  });
}
