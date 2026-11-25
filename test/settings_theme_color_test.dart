import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/l10n/tables/app_l10n_theme.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/ios/ios_device_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/network/host_network_info.dart';
import 'package:any_deck/core/notifications/mac_notification_bridge.dart';
import 'package:any_deck/core/notifications/notification_providers.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/providers/host_network_provider.dart';
import 'package:any_deck/features/overview/settings/settings_workspace.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

/// 隔离原生初始化，保留实际主题色保存与广播流程。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() =>
      const AppSettings(screenshotSavePath: '/tmp/AnyDeck-theme-screenshots');
}

/// 固定未授权状态，仅展示系统设置入口，不访问系统通知权限。
class _DeniedNotifications extends MacNotificationBridge {
  @override
  Future<String> getAuthorizationStatus() async => 'denied';
}

class _SettingsTab extends ToolTabNotifier {
  @override
  int build() => 12;
}

/// 固定主机与 iOS 发现结果，避免测试触发真实网络和设备扫描。
class _HostNetwork extends HostNetworkNotifier {
  @override
  Future<HostNetworkInfo> build() async => const HostNetworkInfo();
}

class _Ios extends IosDeviceService {
  @override
  Future<List<DiscoveredDevice>> listDevices() async => [];
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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('mixin.one/desktop_multi_window');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(
      windows,
      (call) async => call.method == 'getAllWindows' ? <Object>[] : null,
    );
  });
  tearDown(() => messenger.setMockMethodCallHandler(windows, null));

  test('主题色设置中英文文案及全部颜色名称完整', () {
    expect(themeZh.keys.toSet(), themeEn.keys.toSet());
    for (final color in AppThemeColor.values) {
      expect(themeZh[color.labelKey], isNotEmpty);
      expect(themeEn[color.labelKey], isNotEmpty);
    }
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('实际设置页主题色选择、搜索与保存 $language $brightness', (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final notifications = _DeniedNotifications();
        addTearDown(notifications.dispose);
        final container = ProviderContainer(
          overrides: [
            appSettingsProvider.overrideWith(_Settings.new),
            selectedToolTabProvider.overrideWith(_SettingsTab.new),
            adbEnvironmentProvider.overrideWith(_ReadyAdb.new),
            hostNetworkProvider.overrideWith(_HostNetwork.new),
            anyEmulatorRunningProvider.overrideWithValue(false),
            iosDeviceServiceProvider.overrideWithValue(_Ios()),
            adbServiceProvider.overrideWithValue(FakeAdbService()),
            macNotificationBridgeProvider.overrideWithValue(notifications),
            discoveredDevicesProvider.overrideWith(
              (ref) => Stream.value(<DiscoveredDevice>[]),
            ),
          ],
        );
        addTearDown(container.dispose);
        final router = container.read(appRouterProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: Consumer(
              builder: (context, ref, child) {
                final color = ref.watch(
                  appSettingsProvider.select((settings) => settings.themeColor),
                );
                return MaterialApp.router(
                  routerConfig: router,
                  locale: Locale(language),
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: const [
                    AppLocalizationsDelegate(),
                    ...GlobalMaterialLocalizations.delegates,
                  ],
                  theme: buildAppTheme(brightness, themeColor: color),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations(Locale(language));
        final selector = find.byType(PopupMenuButton<AppThemeColor>);
        final search = find.byKey(const ValueKey('settings-search'));
        expect(find.text(l10n.t('themeColor')), findsOneWidget);
        expect(
          tester.widget<PopupMenuButton<AppThemeColor>>(selector).enabled,
          isTrue,
        );

        // 颜色名称可检索同一设置项，定位后仍可正常展开控件。
        await tester.enterText(search, l10n.t(AppThemeColor.blue.labelKey));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-result-themeColor')),
        );
        await tester.pumpAndSettle();
        expect(selector.hitTestable(), findsOneWidget);

        for (final width in [1600.0, 900.0]) {
          tester.view.physicalSize = Size(width, 900);
          await tester.pumpAndSettle();
          final buttonRect = tester.getRect(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          final options = find.byType(PopupMenuItem<AppThemeColor>);
          expect(options, findsNWidgets(AppThemeColor.values.length));
          final menuRect = tester.getRect(options.first);
          expect(menuRect.left, closeTo(buttonRect.left, 0.01));
          expect(menuRect.right, closeTo(buttonRect.right, 0.01));
          expect(menuRect.top, greaterThanOrEqualTo(buttonRect.bottom));
          for (final color in AppThemeColor.values) {
            expect(find.text(l10n.t(color.labelKey)), findsWidgets);
          }
          final selected = width == 1600
              ? AppThemeColor.blue
              : AppThemeColor.green;
          await tester.tap(find.text(l10n.t(selected.labelKey)).last);
          await tester.pumpAndSettle();
          expect(container.read(appSettingsProvider).themeColor, selected);
          expect(
            (await SharedPreferences.getInstance()).getString(
              'settings.themeColor',
            ),
            selected.name,
          );
          expect(
            Theme.of(tester.element(selector)).colorScheme.primary,
            selected.color,
          );
          final swatch = tester.widget<Icon>(
            find.descendant(of: selector, matching: find.byIcon(Icons.circle)),
          );
          expect(swatch.color, selected.color);
          if (selected == AppThemeColor.blue) {
            await tester.enterText(search, l10n.t('deviceConnectNotification'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('settings-result-notifications')),
            );
            await tester.pumpAndSettle();
            final switches = tester.widgetList<CupertinoSwitch>(
              find.byType(CupertinoSwitch),
            );
            expect(switches, isNotEmpty);
            for (final control in switches) {
              expect(control.activeTrackColor, selected.color);
            }
          }
          // 普通目录与权限操作使用主色，清理缓存继续保持危险操作色。
          for (final item in [
            ('notifications', 'notificationPermission', ['openSystemSettings']),
            ('cacheFolders', 'cacheFolders', ['openCacheFolder']),
            (
              'saveDirectory',
              'saveDirectory',
              [
                language == 'zh' ? '打开' : 'Open',
                language == 'zh' ? '更改' : 'Change',
              ],
            ),
          ]) {
            await tester.enterText(search, l10n.t(item.$2));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(ValueKey('settings-result-${item.$1}')),
            );
            await tester.pumpAndSettle();
            for (final key in item.$3) {
              final label = item.$1 == 'saveDirectory' ? key : l10n.t(key);
              expect(
                tester.widget<Text>(find.text(label)).style?.color,
                selected.color,
              );
            }
            if (item.$1 == 'cacheFolders') {
              expect(
                tester
                    .widget<Text>(find.text(l10n.t('clearCache')))
                    .style
                    ?.color,
                const Color(0xFFDC2626),
              );
            }
          }
          await tester.enterText(search, l10n.t('themeColor'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('settings-result-themeColor')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(
          tester
              .widget<SettingsWorkspace>(find.byType(SettingsWorkspace))
              .items
              .where((item) => item.id == 'themeColor'),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      });
    }
  }
}
