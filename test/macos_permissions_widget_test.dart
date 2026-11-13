import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_macos_permissions.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/permissions/mac_permission.dart';
import 'package:any_deck/core/permissions/mac_permissions_controller.dart';
import 'package:any_deck/core/permissions/mac_permissions_service.dart';
import 'package:any_deck/features/overview/settings/macos_permissions_page.dart';
import 'package:any_deck/features/overview/settings/settings_item.dart';
import 'package:any_deck/features/overview/settings/settings_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';

/// 用内存状态模拟系统读写，测试不得弹出真实权限或系统设置。
class _Permissions extends MacPermissionsService {
  int reads = 0;
  bool failRead = false;
  bool failAction = false;
  Completer<void>? requestGate;
  final requests = <MacPermission>[];
  final settings = <MacPermission>[];
  final statuses = {
    for (final permission in MacPermission.values)
      permission: MacPermissionStatus.authorized,
    MacPermission.localNetwork: MacPermissionStatus.manual,
    MacPermission.files: MacPermissionStatus.manual,
    MacPermission.camera: MacPermissionStatus.notDetermined,
    MacPermission.notifications: MacPermissionStatus.denied,
    MacPermission.cameraExtension: MacPermissionStatus.unsupported,
    MacPermission.loginItems: MacPermissionStatus.notRequired,
  };

  @override
  Future<Map<MacPermission, MacPermissionStatus>> readAll() async {
    reads++;
    if (failRead) throw StateError('read failed');
    return Map.of(statuses);
  }

  @override
  Future<void> request(MacPermission permission) async {
    requests.add(permission);
    if (failAction) throw StateError('request failed');
    await requestGate?.future;
    statuses[permission] = MacPermissionStatus.authorized;
  }

  @override
  Future<void> openSettings(MacPermission permission) async {
    settings.add(permission);
    if (failAction) throw StateError('open failed');
  }
}

Widget _app(
  _Permissions service, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
  bool workspace = false,
  bool includePermissions = true,
}) => ProviderScope(
  overrides: [macPermissionsServiceProvider.overrideWithValue(service)],
  child: MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildAppTheme(brightness),
    home: Scaffold(
      body: workspace
          ? Builder(
              builder: (context) => SettingsWorkspace(
                cardBuilder: (title, children) =>
                    Card(child: Column(children: [Text(title), ...children])),
                items: [
                  const SettingsItem(
                    id: 'general',
                    category: SettingsCategory.general,
                    section: 'General',
                    title: 'General',
                    child: Text('General content'),
                  ),
                  if (includePermissions)
                    SettingsItem(
                      id: 'macosPermissions',
                      category: SettingsCategory.permissions,
                      section: context.l10n.t('macPermissionsTitle'),
                      title: context.l10n.t('macPermissionsTitle'),
                      searchLabels: [
                        for (final permission in MacPermission.values)
                          context.l10n.t(permission.titleKey),
                      ],
                      child: const MacPermissionsPanel(),
                    ),
                ],
              ),
            )
          : const SingleChildScrollView(child: MacPermissionsPanel()),
    ),
  ),
);

void main() {
  test('所有权限和状态文案均有中英文且没有依赖回退', () {
    expect(macosPermissionsZh.keys.toSet(), macosPermissionsEn.keys.toSet());
    for (final key in [
      for (final permission in MacPermission.values) ...[
        permission.titleKey,
        permission.descriptionKey,
      ],
      for (final status in MacPermissionStatus.values) status.labelKey,
    ]) {
      expect(macosPermissionsZh, contains(key));
      expect(macosPermissionsEn, contains(key));
    }
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final width in [360.0, 1100.0]) {
        testWidgets('$language $brightness $width 权限用途和状态布局', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final service = _Permissions();
          await tester.pumpWidget(
            _app(service, language: language, brightness: brightness),
          );
          await tester.pumpAndSettle();
          final l10n = AppLocalizations(Locale(language));
          for (final permission in MacPermission.values) {
            expect(find.text(l10n.t(permission.titleKey)), findsOneWidget);
            expect(
              find.text(l10n.t(permission.descriptionKey)),
              findsOneWidget,
            );
          }
          expect(service.reads, 1);
          expect(service.requests, isEmpty);
          expect(service.settings, isEmpty);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(
                    const ValueKey('mac-permission-action-cameraExtension'),
                  ),
                )
                .onPressed,
            isNull,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('未申请的相机点击才申请，拒绝和手动查看项跳转设置', (tester) async {
    final service = _Permissions();
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    final camera = find.byKey(const ValueKey('mac-permission-action-camera'));
    await tester.ensureVisible(camera);
    service.requestGate = Completer<void>();
    await tester.tap(camera);
    await tester.pump();
    expect(service.requests, [MacPermission.camera]);
    expect(tester.widget<OutlinedButton>(camera).onPressed, isNull);
    service.requestGate!.complete();
    await tester.pumpAndSettle();
    final cameraStatus = tester.widget<Text>(
      find.byKey(const ValueKey('mac-permission-status-camera')),
    );
    expect(cameraStatus.data, '已授权');
    for (final permission in [
      MacPermission.notifications,
      MacPermission.files,
    ]) {
      final action = find.byKey(
        ValueKey('mac-permission-action-${permission.name}'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
    }
    expect(service.settings, [
      MacPermission.notifications,
      MacPermission.files,
    ]);
    expect(service.requests, [MacPermission.camera]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('读取失败保留未知状态并可刷新重试，动作失败有提示', (tester) async {
    final service = _Permissions()..failRead = true;
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    expect(find.text('权限状态读取失败，请刷新重试。'), findsOneWidget);
    expect(find.text('状态未知'), findsNWidgets(MacPermission.values.length));
    expect(find.text('已授权'), findsNothing);
    service.failRead = false;
    await tester.tap(find.byKey(const ValueKey('mac-permissions-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mac-permissions-error')), findsNothing);
    service.failAction = true;
    final camera = find.byKey(const ValueKey('mac-permission-action-camera'));
    await tester.ensureVisible(camera);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(find.text('授权申请未完成，请重试或在系统设置中查看。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('返回前台刷新状态，页面销毁后不再刷新', (tester) async {
    final service = _Permissions();
    final listenerCount = windowManager.listeners.length;
    await tester.pumpWidget(_app(service));
    await tester.pumpAndSettle();
    service.statuses[MacPermission.camera] = MacPermissionStatus.denied;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.reads, 2);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('mac-permission-status-camera')),
          )
          .data,
      '未授权',
    );
    expect(windowManager.listeners.length, listenerCount + 1);
    windowManager.listeners.last.onWindowFocus();
    await tester.pumpAndSettle();
    expect(service.reads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.reads, 3);
    expect(windowManager.listeners.length, listenerCount);
    expect(tester.takeException(), isNull);
  });

  testWidgets('权限分类搜索可定位具体权限，未装配的分类不展示', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _Permissions();
    await tester.pumpWidget(_app(service, workspace: true));
    await tester.pumpAndSettle();
    expect(service.reads, 0);
    await tester.enterText(find.byKey(const ValueKey('settings-search')), '相机');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-result-macosPermissions')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-content-permissions')),
      findsOneWidget,
    );
    expect(find.text('相机').hitTestable(), findsOneWidget);
    expect(service.reads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _app(service, workspace: true, includePermissions: false),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-nav-permissions')),
      findsNothing,
    );
    expect(service.reads, 1);
  });
}
