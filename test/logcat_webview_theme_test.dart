import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/logcat/logcat_controller.dart';
import 'package:any_deck/core/logcat/logcat_entry.dart';
import 'package:any_deck/core/logcat/logcat_state.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/webview/in_app_webview_widget.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 保留真实暂停切换行为，隔离日志命令和 Preference 初始化。
class _PausedLogcat extends LogcatController {
  @override
  LogcatState build() => const LogcatState(isRunning: true, isPaused: true);

  @override
  Future<void> start(String deviceId, {bool isHarmony = false}) async {}

  @override
  Future<void> stop() async {}
}

/// 固定两条匹配日志，验证当前搜索项换色及跳转，不运行 Logcat 进程。
class _SearchLogcat extends _PausedLogcat {
  @override
  LogcatState build() => LogcatState(
    isRunning: true,
    viewMode: LogcatViewMode.plain,
    entries: [
      LogcatEntry(rawLine: 'first needle', message: 'first needle'),
      LogcatEntry(rawLine: 'second needle', message: 'second needle'),
    ],
  );
}

/// 浏览器主题回归只挂载 Flutter 工具栏，避免打开原生网页。
class _WebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _WebView(params);
}

class _WebView extends PlatformInAppWebViewWidget {
  _WebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      InAppWebViewController.fromPlatform(platform: controller) as T;

  @override
  void dispose() {}
}

Widget _app(Widget child, Brightness brightness, AppThemeColor color) =>
    MaterialApp(
      theme: buildAppTheme(brightness, themeColor: color),
      themeAnimationDuration: Duration.zero,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: child),
    );

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} Logcat 当前搜索项换色后保留查询与跳转', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final scope = ProviderContainer(
        overrides: [logcatControllerProvider.overrideWith(_SearchLogcat.new)],
      );
      addTearDown(scope.dispose);
      final panel = UncontrolledProviderScope(
        container: scope,
        child: const LogcatTab(
          device: DiscoveredDevice(id: 'phone', status: 'device'),
          isVisible: false,
        ),
      );
      await tester.pumpWidget(_app(panel, brightness, AppThemeColor.blue));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first needle'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.focusNode?.debugLabel == 'LogcatSearchInput',
      );
      await tester.enterText(search, 'needle');
      await tester.pumpAndSettle();
      final before = scope.read(logcatControllerProvider);
      for (final selected in [AppThemeColor.blue, AppThemeColor.pink]) {
        await tester.pumpWidget(_app(panel, brightness, selected));
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(search));
        final matches = tester
            .widgetList<Text>(find.byType(Text))
            .map((widget) => widget.textSpan)
            .whereType<TextSpan>()
            .expand((span) => span.children ?? <InlineSpan>[])
            .whereType<TextSpan>()
            .where((span) => span.text == 'needle');
        expect(
          matches
              .where(
                (span) =>
                    span.style?.backgroundColor ==
                    theme.colorScheme.primaryContainer,
              )
              .length,
          1,
        );
        expect(
          matches
              .singleWhere((span) => span.style?.fontWeight == FontWeight.bold)
              .style!
              .color,
          theme.colorScheme.onPrimaryContainer,
        );
        expect(
          matches
              .where(
                (span) =>
                    span.style?.backgroundColor ==
                    Colors.yellow.withValues(alpha: 0.4),
              )
              .length,
          1,
        );
        expect(tester.widget<TextField>(search).controller!.text, 'needle');
        expect(find.text('1 / 2'), findsOneWidget);
        expect(scope.read(logcatControllerProvider), same(before));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('${brightness.name} Logcat 暂停按钮换色后可正常恢复采集', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scope = ProviderContainer(
        overrides: [logcatControllerProvider.overrideWith(_PausedLogcat.new)],
      );
      addTearDown(scope.dispose);
      final panel = UncontrolledProviderScope(
        container: scope,
        child: const LogcatTab(
          device: DiscoveredDevice(id: 'phone', status: 'device'),
          isVisible: false,
        ),
      );
      for (final color in [AppThemeColor.blue, AppThemeColor.purple]) {
        await tester.pumpWidget(_app(panel, brightness, color));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Icon>(find.byIcon(CupertinoIcons.play)).color,
          color.color,
        );
        expect(scope.read(logcatControllerProvider).isPaused, isTrue);
      }
      await tester.tap(find.byIcon(CupertinoIcons.play));
      await tester.pump();
      expect(scope.read(logcatControllerProvider).isPaused, isFalse);
      expect(find.byIcon(CupertinoIcons.pause), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('${brightness.name} WebView 地址栏图标动态换色并保留输入网址', (tester) async {
      // 未注册原生平台时保留有效占位，平台 setter 不接受恢复为 null。
      final previousPlatform =
          InAppWebViewPlatform.instance ?? _WebViewPlatform();
      InAppWebViewPlatform.instance = _WebViewPlatform();
      addTearDown(() => InAppWebViewPlatform.instance = previousPlatform);
      const browser = InAppWebViewWidget(initialUrl: 'https://example.com');
      await tester.pumpWidget(_app(browser, brightness, AppThemeColor.blue));
      await tester.enterText(find.byType(TextField), 'https://example.org');
      for (final color in [AppThemeColor.blue, AppThemeColor.purple]) {
        await tester.pumpWidget(_app(browser, brightness, color));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Icon>(find.byIcon(CupertinoIcons.lock_shield_fill))
              .color,
          color.color,
        );
        expect(find.text('https://example.org'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
