import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:any_deck/core/notifications/notification_providers.dart';
import 'package:any_deck/features/harmony_share/widgets/harmony_share_settings_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 仅隔离持久化与窗口广播，实际设置弹窗、MethodChannel 与权限流程照常执行。
class _Settings extends AppSettingsController {
  _Settings(this.enabled);
  final bool enabled;
  @override
  AppSettings build() => AppSettings(harmonyShareNotifications: enabled);
  @override
  Future<void> setHarmonyShareNotifications(
    bool value, {
    bool broadcast = true,
  }) async {
    state = state.copyWith(harmonyShareNotifications: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void permissionWidgetTest(
    String name,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  const channel = MethodChannel('test/harmony_permission_request');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  late MacNotificationBridge bridge;
  dynamic response;
  var requested = false;
  var completedState = 'notDetermined';

  setUp(() {
    calls.clear();
    requested = false;
    completedState = 'notDetermined';
    response = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'getAuthorizationStatus') {
        return requested ? completedState : 'notDetermined';
      }
      if (call.method == 'requestAuthorization') {
        requested = true;
        if (response is PlatformException) throw response as PlatformException;
        return response;
      }
      return true;
    });
    bridge = MacNotificationBridge(channel: channel);
  });
  tearDown(() {
    bridge.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Widget host(String language, Brightness brightness, {bool enabled = true}) =>
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(() => _Settings(enabled)),
          macNotificationBridgeProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp(
          theme: buildAppTheme(brightness),
          locale: Locale(language),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: const Scaffold(body: HarmonyShareSettingsDialog()),
        ),
      );

  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      for (final failure in ['channel', 'missing', 'malformed', 'unresolved']) {
        permissionWidgetTest(
          '授权请求异常 $failure 保留系统状态并提供设置入口 ${brightness.name} $language',
          (tester) async {
            tester.view.physicalSize = const Size(480, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            response = switch (failure) {
              'channel' => PlatformException(
                code: 'authorization_failed',
                message: '/private/diagnostic',
              ),
              'missing' => null,
              'unresolved' => false,
              _ => 42,
            };
            final l10n = AppLocalizations(Locale(language));
            await tester.pumpWidget(host(language, brightness));
            await tester.pumpAndSettle();
            final request = find.text(l10n.t('requestPermission'));
            await tester.ensureVisible(request);
            await tester.tap(request);
            await tester.pumpAndSettle();
            expect(
              find.text(l10n.t('harmonySharePermissionRequestFailed')),
              findsOneWidget,
            );
            expect(
              find.text(l10n.t('harmonySharePermissionNeeded')),
              findsOneWidget,
            );
            expect(
              find.text(l10n.t('harmonySharePermissionUnknown')),
              findsNothing,
            );
            expect(find.text('/private/diagnostic'), findsNothing);
            expect(find.text(l10n.t('requestPermission')), findsNothing);
            final settings = find.text(l10n.t('openSystemSettings'));
            await tester.ensureVisible(settings);
            await tester.tap(settings);
            await tester.pumpAndSettle();
            expect(
              calls.where((v) => v == 'requestAuthorization'),
              hasLength(1),
            );
            expect(
              calls.where((v) => v == 'openNotificationSettings'),
              hasLength(1),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final granted in [true, false]) {
    permissionWidgetTest('合法授权结果 $granted 显示真实状态', (tester) async {
      response = granted;
      completedState = granted ? 'authorized' : 'denied';
      await tester.pumpWidget(host('zh', Brightness.light));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations(const Locale('zh'));
      final request = find.text(l10n.t('requestPermission'));
      await tester.ensureVisible(request);
      await tester.tap(request);
      await tester.pumpAndSettle();
      expect(
        find.text(
          l10n.t(
            granted
                ? 'notificationPermissionGranted'
                : 'notificationPermissionDenied',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(l10n.t('harmonySharePermissionRequestFailed')),
        findsNothing,
      );
      expect(calls.where((v) => v == 'requestAuthorization'), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  permissionWidgetTest('开启通知后的授权故障不会回滚已保存开关', (tester) async {
    response = PlatformException(code: 'authorization_failed');
    await tester.pumpWidget(host('zh', Brightness.light, enabled: false));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(
      find.text(
        AppLocalizations(
          const Locale('zh'),
        ).t('harmonySharePermissionRequestFailed'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final success in [true, false]) {
    permissionWidgetTest('关闭弹窗后忽略迟到${success ? '成功' : '失败'}且不再查询权限', (
      tester,
    ) async {
      final pending = Completer<bool>();
      response = pending.future;
      await tester.pumpWidget(host('zh', Brightness.light));
      await tester.pumpAndSettle();
      final request = find.text(
        AppLocalizations(const Locale('zh')).t('requestPermission'),
      );
      await tester.ensureVisible(request);
      await tester.tap(request);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      if (success) {
        pending.complete(true);
      } else {
        pending.completeError(PlatformException(code: 'authorization_failed'));
      }
      await tester.pumpAndSettle();
      expect(calls.where((v) => v == 'requestAuthorization'), hasLength(1));
      expect(calls.where((v) => v == 'getAuthorizationStatus'), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  permissionWidgetTest('申请超时后保持未确定，手动刷新可恢复真实授权状态', (tester) async {
    final pending = Completer<bool>();
    response = pending.future;
    final l10n = AppLocalizations(const Locale('zh'));
    await tester.pumpWidget(host('zh', Brightness.light));
    await tester.pumpAndSettle();
    final request = find.text(l10n.t('requestPermission'));
    await tester.ensureVisible(request);
    await tester.tap(request);
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.t('harmonySharePermissionRequestFailed')),
      findsOneWidget,
    );
    expect(find.text(l10n.t('harmonySharePermissionNeeded')), findsOneWidget);
    completedState = 'authorized';
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.text(l10n.t('notificationPermissionGranted')), findsNothing);
    final refresh = find.byTooltip(l10n.t('harmonySharePermissionRefresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.text(l10n.t('notificationPermissionGranted')), findsOneWidget);
    expect(
      find.text(l10n.t('harmonySharePermissionRequestFailed')),
      findsNothing,
    );
    expect(calls.where((v) => v == 'requestAuthorization'), hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
