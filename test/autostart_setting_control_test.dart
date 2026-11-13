import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_autostart.dart';
import 'package:any_deck/app/settings/desktop_autostart_service.dart';
import 'package:any_deck/features/overview/settings/autostart_setting_control.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

/// 内存状态模拟系统批准，不注册真实登录项或写用户配置。
class _System {
  DesktopAutoStartStatus status = DesktopAutoStartStatus.requiresApproval;
  final updates = <bool>[];
  int reads = 0;
  int opened = 0;
  bool failOpen = false;
  Completer<void>? gate;

  Future<DesktopAutoStartStatus> read() async {
    reads++;
    return status;
  }

  Future<void> update(bool enabled) async {
    updates.add(enabled);
    await gate?.future;
    status = enabled
        ? DesktopAutoStartStatus.requiresApproval
        : DesktopAutoStartStatus.disabled;
  }

  Future<void> open() async {
    opened++;
    if (failOpen) throw StateError('settings failed');
    await gate?.future;
  }
}

Widget _app(
  _System system, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) => ProviderScope(
  overrides: [
    autoStartStatusProvider.overrideWith((ref) => system.read()),
    autoStartUpdateProvider.overrideWithValue(system.update),
    autoStartOpenSettingsProvider.overrideWithValue(system.open),
  ],
  child: MaterialApp(
    locale: Locale(language),
    theme: ThemeData(brightness: brightness),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: const Scaffold(
      body: SingleChildScrollView(child: AutoStartSettingControl()),
    ),
  ),
);

void main() {
  for (final pendingMethod in ['status', 'openSettings']) {
    testWidgets('$pendingMethod 原生未返回时销毁入口取消等待Timer并忽略迟到结果', (tester) async {
      const channel = MethodChannel('any_deck/autostart');
      final gate = Completer<Object?>();
      final messenger = tester.binding.defaultBinaryMessenger;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == pendingMethod) return gate.future;
        return 'requiresApproval';
      });
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                ...GlobalMaterialLocalizations.delegates,
              ],
              locale: const Locale('zh'),
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: AutoStartSettingControl()),
            ),
          ),
        );
        await tester.pump();
        if (pendingMethod == 'openSettings') {
          await tester.tap(
            find.byKey(const ValueKey('autostart-open-settings')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('autostart-open-settings')),
                )
                .onPressed,
            isNull,
          );
          expect(find.text('无法打开系统设置，请从 Apple 菜单手动进入。'), findsNothing);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.complete(pendingMethod == 'status' ? 'enabled' : null);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
  test('自启批准提示的中英文键完整', () {
    expect(autoStartZh.keys.toSet(), autoStartEn.keys.toSet());
    expect(autoStartEn.values.every((value) => value.isNotEmpty), isTrue);
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('$language $brightness 窄窗口待批准提示和设置入口', (tester) async {
        tester.view.physicalSize = const Size(360, 500);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final system = _System();
        await tester.pumpWidget(
          _app(system, language: language, brightness: brightness),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('autostart-status')), findsOneWidget);
        expect(system.updates, isEmpty);
        await tester.tap(find.byKey(const ValueKey('autostart-open-settings')));
        await tester.pumpAndSettle();
        expect(system.opened, 1);
        expect(system.status, DesktopAutoStartStatus.requiresApproval);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('开启后待批准仍可取消注册，开关不自动注册', (tester) async {
    final system = _System()..status = DesktopAutoStartStatus.disabled;
    await tester.pumpWidget(_app(system));
    await tester.pumpAndSettle();
    expect(system.updates, isEmpty);
    tester
        .widget<CupertinoSwitch>(find.byKey(const ValueKey('autostart-switch')))
        .onChanged!(true);
    await tester.pumpAndSettle();
    expect(system.updates, [true]);
    expect(find.text('登录项已注册，等待你在系统设置中批准。'), findsOneWidget);
    final pendingSwitch = tester.widget<CupertinoSwitch>(
      find.byKey(const ValueKey('autostart-switch')),
    );
    expect(pendingSwitch.value, isTrue);
    expect(pendingSwitch.onChanged, isNotNull);
    pendingSwitch.onChanged!(false);
    await tester.pumpAndSettle();
    expect(system.updates, [true, false]);
    expect(find.byKey(const ValueKey('autostart-open-settings')), findsNothing);
    expect(
      tester
          .widget<CupertinoSwitch>(
            find.byKey(const ValueKey('autostart-switch')),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('旧系统配置可取消，不将manual显示成已批准', (tester) async {
    final system = _System()..status = DesktopAutoStartStatus.manual;
    await tester.pumpWidget(_app(system));
    await tester.pumpAndSettle();
    expect(find.text('自启配置已保存，请在系统登录项中确认是否允许运行。'), findsOneWidget);
    tester
        .widget<CupertinoSwitch>(find.byKey(const ValueKey('autostart-switch')))
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(system.updates, [false]);
    expect(system.status, DesktopAutoStartStatus.disabled);
  });

  testWidgets('打开设置防重复且失败可重试，不伪造批准', (tester) async {
    final system = _System()..failOpen = true;
    await tester.pumpWidget(_app(system));
    await tester.pumpAndSettle();
    final action = find.byKey(const ValueKey('autostart-open-settings'));
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('无法打开系统设置，请从 Apple 菜单手动进入。'), findsOneWidget);
    system.failOpen = false;
    system.gate = Completer<void>();
    await tester.tap(action);
    await tester.pump();
    expect(tester.widget<TextButton>(action).onPressed, isNull);
    system.gate!.complete();
    await tester.pumpAndSettle();
    expect(system.opened, 2);
    expect(system.status, DesktopAutoStartStatus.requiresApproval);
    expect(find.text('无法打开系统设置，请从 Apple 菜单手动进入。'), findsNothing);
  });

  testWidgets('回到前台和窗口聚焦读取新状态，销毁后移除监听', (tester) async {
    final system = _System();
    final count = windowManager.listeners.length;
    await tester.pumpWidget(_app(system));
    await tester.pumpAndSettle();
    system.status = DesktopAutoStartStatus.enabled;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(system.reads, 2);
    expect(find.byKey(const ValueKey('autostart-open-settings')), findsNothing);
    windowManager.listeners.last.onWindowFocus();
    await tester.pumpAndSettle();
    expect(system.reads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(windowManager.listeners.length, count);
  });

  testWidgets('销毁后迟到的注册结果不更新页面', (tester) async {
    final system = _System()
      ..status = DesktopAutoStartStatus.disabled
      ..gate = Completer<void>();
    await tester.pumpWidget(_app(system));
    await tester.pumpAndSettle();
    tester
        .widget<CupertinoSwitch>(find.byKey(const ValueKey('autostart-switch')))
        .onChanged!(true);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    system.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
