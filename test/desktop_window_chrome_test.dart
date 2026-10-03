import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/controller/desktop_caption_controller.dart';
import 'package:any_deck/app/window/desktop_window_title_service.dart';
import 'package:any_deck/app/window/model/desktop_chrome_policy.dart';
import 'package:any_deck/app/window/widget/desktop_window_frame.dart';
import 'package:any_deck/app/window/widget/desktop_workspace_surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

// 使用窗口通道桩验证宿主平台分流，不启动桌面窗口或 ADB。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final calls = <MethodCall>[];
  var maximized = false;
  var fullScreen = false;

  setUp(() {
    calls.clear();
    maximized = false;
    fullScreen = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'isMaximized':
              return maximized;
            case 'isFocused':
              return true;
            case 'isFullScreen':
              return fullScreen;
            case 'maximize':
              maximized = true;
            case 'unmaximize':
              maximized = false;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget app({
    String language = 'zh',
    Brightness brightness = Brightness.light,
  }) {
    return MaterialApp(
      theme: buildAppTheme(brightness),
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => DesktopWindowFrame(
        title: '${context.l10n.t('appTitle')} ${'Window title ' * 20}',
        child: child!,
      ),
      home: const Scaffold(body: Text('workspace')),
    );
  }

  test('平台策略保留 macOS 按钮与 Linux 原生装饰，子窗口不缺少控制按钮', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      final policy = DesktopChromePolicy(platform);
      expect(
        policy.mainTitleBarStyle,
        platform == TargetPlatform.linux
            ? TitleBarStyle.normal
            : TitleBarStyle.hidden,
      );
      expect(
        policy.subWindowTitleBarStyle,
        platform == TargetPlatform.macOS
            ? TitleBarStyle.hidden
            : TitleBarStyle.normal,
      );
      expect(
        policy.toolbarLeadingInset,
        platform == TargetPlatform.macOS ? 80 : 0,
      );
    }
  });

  testWidgets('Windows 窄窗口长标题不溢出，动作走原生关闭与最大化通道', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(700, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final listenersBefore = windowManager.listeners.length;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('最大化'), findsOneWidget);
    expect(tester.getTopLeft(find.text('workspace')).dy, 36);
    await tester.tap(find.byTooltip('最大化'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('还原窗口'), findsOneWidget);
    await tester.tap(find.byTooltip('还原窗口'));
    await tester.pumpAndSettle();
    expect(maximized, isFalse);
    await tester.tap(find.byTooltip('最小化'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(
      calls.map((call) => call.method),
      containsAll(['maximize', 'unmaximize', 'minimize', 'close']),
    );
    expect(calls.map((call) => call.method), isNot(contains('destroy')));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(windowManager.listeners.length, listenersBefore);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('标题栏 Tooltip 可在路由外显示，英文暗色切换不丢失内容', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(app(language: 'en', brightness: Brightness.dark));
    await tester.pumpAndSettle();
    final tooltip = tester.state<TooltipState>(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'Minimize',
      ),
    );
    tooltip.ensureTooltipVisible();
    await tester.pumpAndSettle();
    expect(find.text('Minimize'), findsOneWidget);
    expect(find.text('workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
    testWidgets('$platform 不重复绘制 Windows 控制栏', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭'), findsNothing);
      expect(tester.getTopLeft(find.text('workspace')).dy, 0);
      expect(calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('系统全屏事件隐藏标题栏，退出全屏恢复', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    fullScreen = true;
    for (final listener in windowManager.listeners) {
      listener.onWindowEvent('enter-full-screen');
    }
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭'), findsNothing);
    fullScreen = false;
    for (final listener in windowManager.listeners) {
      listener.onWindowEvent('leave-full-screen');
    }
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Windows/Linux 工作区不挂载 BackdropFilter', (tester) async {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(
        MaterialApp(
          home: const DesktopWorkspaceSurface(child: Text('content')),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('Windows/Linux 原生标题通过所有子引擎可用的窗口通道同步', () async {
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      await DesktopWindowTitleService.setTitle('窗口 Window');
      expect(calls.last.method, 'setTitle');
      expect(calls.last.arguments, {'title': '窗口 Window'});
    }
  });

  test('异步窗口动作完成前销毁 controller，不再通知已卸载 Widget', () async {
    final pending = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') await pending.future;
          return false;
        });
    final controller = DesktopCaptionController();
    final action = controller.close();
    controller.dispose();
    pending.complete();
    await action;
  });
}
