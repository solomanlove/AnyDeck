import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/router/dashboard_route.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/shortcuts/keyboard_shortcut_binding.dart';
import 'package:any_deck/app/shortcuts/window_shortcut.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/app/window/window_shortcut_bridge.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_adb_service.dart';
import 'support/shortcut_test_fixture.dart';

/// 使用真实主窗口路由与 Dashboard，隔离设备发现和原生窗口操作。
class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class _SettingsTab extends ToolTabNotifier {
  @override
  int build() => 12;
}

class _Settings extends ShortcutTestSettings {
  @override
  AppSettings build() => const AppSettings(showWindowShortcutKey: '5');
}

class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo();
}

class _ReadyAdb extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() =>
      const AdbEnvironmentInfo(status: AdbEnvironmentStatus.ready);

  @override
  Future<void> checkAndPromptIfNeeded(BuildContext context) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = ShortcutPlatformMocks();
  setUp(platform.setUp);
  tearDown(platform.tearDown);

  final platforms = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  testWidgets('真实设置路由初始、切页和搜索失焦后均响应四项窗口快捷键', (tester) async {
    await _withDashboard(tester, (container, router) async {
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      expect(
        find.byElementPredicate(
          (element) => element == FocusManager.instance.primaryFocus?.context,
        ),
        findsOneWidget,
        reason: '初始焦点必须位于可见页面，不能落入 Offstage 的路由 Navigator',
      );
      platform.windowCalls.clear();
      await _primary(tester, LogicalKeyboardKey.digit5);
      expect(platform.windowCalls, ['isMinimized', 'show', 'focus']);
      platform.windowCalls.clear();
      await _primary(tester, LogicalKeyboardKey.keyW);
      expect(platform.windowCalls, ['close']);

      router.goNamed(AppRouteNames.devices);
      await tester.pumpAndSettle();
      await _primary(tester, LogicalKeyboardKey.comma);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/settings');
      // 设置搜索打开结果后会主动 unfocus，窗口操作仍应可用。
      await tester.enterText(
        find.byKey(const ValueKey('settings-search')),
        '快捷键',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-result-keyboardShortcuts')),
      );
      await tester.pumpAndSettle();
      platform.windowCalls.clear();
      await _primary(tester, LogicalKeyboardKey.digit5);
      await _primary(tester, LogicalKeyboardKey.keyW);
      expect(platform.windowCalls, ['isMinimized', 'show', 'focus', 'close']);
      await _primary(tester, LogicalKeyboardKey.keyQ);
      final quit = container
          .read(appSettingsProvider)
          .windowShortcuts
          .bindingFor(WindowShortcut.quitApp);
      expect(find.text(_quitPrompt(quit)), findsOneWidget);
    });
  }, variant: platforms);

  testWidgets('真实设置录入四项完整组合，弹窗隔离且新组合立即响应、旧组合失效', (tester) async {
    await _withDashboard(
      tester,
      (container, router) async {
        await tester.tap(find.byKey(const ValueKey('settings-nav-shortcuts')));
        await tester.pumpAndSettle();
        const show = KeyboardShortcutBinding(
          key: LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
        );
        const close = KeyboardShortcutBinding(
          key: LogicalKeyboardKey.f8,
          alt: true,
        );
        const settings = KeyboardShortcutBinding(key: LogicalKeyboardKey.f9);
        const quit = KeyboardShortcutBinding(
          key: LogicalKeyboardKey.keyX,
          control: true,
          alt: true,
          shift: true,
        );
        for (final (id, binding) in [
          ('shortcut-main-window', show),
          ('shortcut-window-closeWindow', close),
          ('shortcut-window-openSettings', settings),
          ('shortcut-window-quitApp', quit),
        ]) {
          final button = find.byKey(ValueKey(id));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
          if (id == 'shortcut-main-window') {
            platform.windowCalls.clear();
            for (final key in [
              LogicalKeyboardKey.digit5,
              LogicalKeyboardKey.keyW,
              LogicalKeyboardKey.comma,
              LogicalKeyboardKey.keyQ,
            ]) {
              await _primary(tester, key);
              expect(find.byType(AlertDialog), findsOneWidget);
              expect(platform.windowCalls, isEmpty);
            }
            final currentQuit = container
                .read(appSettingsProvider)
                .windowShortcuts
                .bindingFor(WindowShortcut.quitApp);
            expect(find.text(_quitPrompt(currentQuit, 'en')), findsNothing);
          }
          await _press(tester, binding);
          await tester.tap(find.byKey(const ValueKey('shortcut-record-save')));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.descendant(of: button, matching: find.text(binding.label())),
            findsOneWidget,
          );
        }
        final configured = container.read(appSettingsProvider);
        expect(configured.mainWindowBinding, show);
        expect(
          configured.windowShortcuts.bindingFor(WindowShortcut.closeWindow),
          close,
        );
        expect(
          configured.windowShortcuts.bindingFor(WindowShortcut.openSettings),
          settings,
        );
        expect(
          configured.windowShortcuts.bindingFor(WindowShortcut.quitApp),
          quit,
        );
        AppToast.dismiss();

        router.goNamed(AppRouteNames.devices);
        await tester.pumpAndSettle();
        platform.windowCalls.clear();
        for (final key in [
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.comma,
          LogicalKeyboardKey.keyQ,
        ]) {
          await _primary(tester, key);
        }
        expect(platform.windowCalls, isEmpty);
        expect(router.routeInformationProvider.value.uri.path, '/devices');
        expect(find.byKey(const Key('appToast')), findsNothing);
        await _press(tester, show);
        await _press(tester, close);
        expect(platform.windowCalls, ['isMinimized', 'show', 'focus', 'close']);
        await _press(tester, settings);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/settings');
        await _press(tester, quit);
        expect(find.text(_quitPrompt(quit, 'en')), findsOneWidget);
      },
      language: 'en',
      brightness: Brightness.dark,
    );
  }, variant: platforms);
}

/// 保留真实 ShellRoute / 设置页面，测试结束前释放 Channel、通知和轻提示计时器。
Future<void> _withDashboard(
  WidgetTester tester,
  Future<void> Function(ProviderContainer container, GoRouter router) run, {
  String language = 'zh',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(1600, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      appSettingsProvider.overrideWith(_Settings.new),
      adbServiceProvider.overrideWithValue(FakeAdbService()),
      discoveredDevicesProvider.overrideWith(
        (ref) => Stream.value(<DiscoveredDevice>[]),
      ),
      deviceRegistryProvider.overrideWith(_Registry.new),
      selectedToolTabProvider.overrideWith(_SettingsTab.new),
      hostNetworkProvider.overrideWith(_HostNetwork.new),
      adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
      emulatorListProvider.overrideWith((ref) async => []),
      emulatorConnectionsProvider.overrideWith((ref) async => {}),
    ],
  );
  final router = container.read(appRouterProvider);
  const notifications = MethodChannel('any_deck/notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    notifications,
    (call) async => call.method == 'ready' ? [] : null,
  );
  try {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildAppTheme(brightness),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await run(container, router);
  } finally {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await WindowShortcutBridge.settled;
    container.dispose();
    await tester.pump();
    messenger.setMockMethodCallHandler(notifications, null);
  }
}

String _quitPrompt(KeyboardShortcutBinding binding, [String language = 'zh']) =>
    AppLocalizations(
      Locale(language),
    ).t('pressShortcutAgainToQuit').replaceAll('{shortcut}', binding.label());

Future<void> _primary(WidgetTester tester, LogicalKeyboardKey key) =>
    _press(tester, KeyboardShortcutBinding.primary(key));

Future<void> _press(WidgetTester tester, KeyboardShortcutBinding binding) =>
    pressShortcut(
      tester,
      binding.key!,
      modifiers: [
        if (binding.control) LogicalKeyboardKey.controlLeft,
        if (binding.alt) LogicalKeyboardKey.altLeft,
        if (binding.shift) LogicalKeyboardKey.shiftLeft,
        if (binding.meta) LogicalKeyboardKey.metaLeft,
      ],
    );
