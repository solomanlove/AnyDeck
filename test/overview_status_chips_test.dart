import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_battery_info.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证概览电量与 Root 标签的中性色及满电精简展示，不启动设备查询。
void main() {
  for (final brightness in Brightness.values) {
    for (final language in ['zh', 'en']) {
      testWidgets('满电与已 Root 使用灰色且隐藏满电文案 $brightness $language', (
        tester,
      ) async {
        await _pumpOverview(
          tester,
          brightness: brightness,
          language: language,
          battery: const DeviceBatteryInfo(
            level: 100,
            chargingState: DeviceChargingState.full,
          ),
          rooted: true,
        );
        final l10n = AppLocalizations(Locale(language));

        expect(find.text(l10n.t('batteryFull')), findsNothing);
        _expectChipStyle(tester, '100%', CupertinoIcons.battery_100);
        _expectChipStyle(
          tester,
          l10n.t('rooted'),
          CupertinoIcons.lock_open_fill,
        );

        // 移除满电文字时同时收回其间距，右侧只保留标签的正常内边距。
        final batteryChip = _chipContaining(find.text('100%'));
        final rightPadding =
            tester.getBottomRight(batteryChip).dx -
            tester.getBottomRight(find.text('100%')).dx;
        expect(rightPadding, closeTo(12, 0.01));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('充电中与未 Root 保留状态文字并使用灰色', (tester) async {
    await _pumpOverview(
      tester,
      language: 'en',
      battery: const DeviceBatteryInfo(
        level: 62,
        chargingState: DeviceChargingState.charging,
      ),
      rooted: false,
    );
    const l10n = AppLocalizations(Locale('en'));

    expect(find.text(l10n.t('batteryCharging')), findsOneWidget);
    _expectChipStyle(tester, '62%', CupertinoIcons.battery_75_percent);
    _expectChipStyle(tester, l10n.t('unrooted'), CupertinoIcons.lock_fill);
    expect(tester.takeException(), isNull);
  });

  testWidgets('低电量和未知 Root 在深色主题下保持灰色', (tester) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.dark,
      battery: const DeviceBatteryInfo(
        level: 10,
        chargingState: DeviceChargingState.notCharging,
      ),
    );
    const l10n = AppLocalizations(Locale('zh'));

    expect(find.text(l10n.t('batteryNotCharging')), findsOneWidget);
    _expectChipStyle(tester, '10%', CupertinoIcons.battery_25);
    _expectChipStyle(
      tester,
      l10n.t('rootStatusUnknown'),
      CupertinoIcons.lock_fill,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('电量缺失时保留未知占位及灰色样式', (tester) async {
    await _pumpOverview(tester);
    const l10n = AppLocalizations(Locale('zh'));

    expect(find.text(l10n.t('batteryUnknown')), findsOneWidget);
    _expectChipStyle(tester, '--%', CupertinoIcons.battery_0);
    _expectChipStyle(
      tester,
      l10n.t('rootStatusUnknown'),
      CupertinoIcons.lock_fill,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('离线设备不展示缓存满电或已 Root 状态', (tester) async {
    await _pumpOverview(
      tester,
      brightness: Brightness.dark,
      language: 'en',
      online: false,
      battery: const DeviceBatteryInfo(
        level: 100,
        chargingState: DeviceChargingState.full,
      ),
      rooted: true,
    );
    const l10n = AppLocalizations(Locale('en'));

    expect(find.text('100%'), findsNothing);
    expect(find.text(l10n.t('rooted')), findsNothing);
    expect(find.text(l10n.t('batteryFull')), findsNothing);
    _expectChipStyle(tester, '--%', CupertinoIcons.battery_0);
    _expectChipStyle(
      tester,
      l10n.t('rootStatusUnknown'),
      CupertinoIcons.lock_fill,
    );
    expect(tester.takeException(), isNull);
  });
}

/// 从可见文案定位胶囊背景，避免依赖私有 Widget 名称。
Finder _chipContaining(Finder text) => find.ancestor(
  of: text,
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).borderRadius ==
            BorderRadius.circular(999),
  ),
);

/// 同时检查文字、图标和背景，防止只替换文字而遗留绿色底色。
void _expectChipStyle(WidgetTester tester, String label, IconData icon) {
  final text = find.text(label);
  expect(text, findsOneWidget);
  final neutral = Theme.of(tester.element(text)).colorScheme.onSurfaceVariant;
  final chip = _chipContaining(text);
  expect(chip, findsOneWidget);
  final decoration =
      tester.widget<DecoratedBox>(chip).decoration as BoxDecoration;
  expect(decoration.color, neutral.withValues(alpha: 0.1));
  for (final text in tester.widgetList<Text>(
    find.descendant(of: chip, matching: find.byType(Text)),
  )) {
    expect(text.style?.color, neutral);
  }
  final chipIcon = find.descendant(of: chip, matching: find.byIcon(icon));
  expect(chipIcon, findsOneWidget);
  expect(tester.widget<Icon>(chipIcon).color, neutral);
}

/// 用缓存概览和受控 Root Provider 渲染真实页面，隔离 ADB 与设备心跳。
Future<void> _pumpOverview(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  String language = 'zh',
  DeviceBatteryInfo? battery,
  bool? rooted,
  bool online = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceRootStatusProvider('test').overrideWith((ref) async => rooted),
      ],
      child: MaterialApp(
        locale: Locale(language),
        theme: buildAppTheme(brightness),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: DeviceOverviewContent(
            device: DiscoveredDevice(
              id: 'test',
              status: online ? 'device' : 'offline',
            ),
            overview: DeviceOverview.fromJson({
              'name': 'Mi MIX 3',
              'brand': 'Xiaomi',
              'androidVersion': 'Android 15 (API 35)',
              if (battery != null) 'battery': battery.toJson(),
            }),
            onRefresh: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
