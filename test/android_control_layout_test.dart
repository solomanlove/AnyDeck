import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/router/app_router.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/widget/app_toast.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';
import 'support/dashboard_test_environment.dart';

const _phone = DiscoveredDevice(id: 'control-layout', status: 'device');

/// 从设备路由加载完整控制页，同时隔离 ADB 与宿主机探测。
class _Registry extends DeviceRegistryNotifier {
  _Registry(this.online);
  final bool online;

  @override
  List<RegisteredDevice> build() => [
    RegisteredDevice(
      id: _phone.id,
      serial: _phone.id,
      model: 'AnyDeck test phone',
      status: online ? 'device' : 'offline',
      isOnline: online,
    ),
  ];
}

/// 记录真实控件送出的参数，用于验证相邻输入框和提交按钮正确配对。
class _ControlAdb extends FakeAdbService {
  final commands = <List<String>>[];

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    commands.add([deviceId, ...args]);
    return super.shellArgs(deviceId, args, timeout: timeout);
  }
}

Future<_ControlAdb> _openControl(
  WidgetTester tester, {
  required Size size,
  required AppLocalizations l10n,
  required Brightness brightness,
  bool online = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final adb = _ControlAdb();
  final overview = DeviceOverview.fromJson({
    'serial': _phone.id,
    'name': 'AnyDeck test phone',
    'resolution': '1080x2400 (440dpi)',
    'fontScale': '1x',
  });
  final container = ProviderContainer(
    overrides: [
      ...dashboardTestPlatformOverrides(),
      adbServiceProvider.overrideWithValue(adb),
      deviceRegistryProvider.overrideWith(() => _Registry(online)),
      discoveredDevicesProvider.overrideWith(
        (ref) => Stream.value(online ? [_phone] : []),
      ),
      deviceOverviewProvider(
        _phone.id,
      ).overrideWith((ref) => Stream.value(overview)),
      cachedDeviceOverviewProvider(
        _phone.id,
      ).overrideWith((ref) async => overview),
      isDeviceRootProvider(_phone.id).overrideWith((ref) async => false),
    ],
  );
  addTearDown(() async {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump();
  });
  final router = container.read(appRouterProvider)
    ..go('/devices/${_phone.id}/control');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: l10n.locale,
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
  return adb;
}

const _quickGroups = {
  'controlDeviceInteraction': [
    'deviceSettings',
    'inputText',
    'controlShowNotifications',
    'expandSettings',
    'focus',
    'lockScreen',
    'remoteController',
  ],
  'controlSystemToggles': [
    'wifiToggle',
    'airplaneModeToggle',
    'mobileDataToggle',
    'talkbackToggle',
    'autoRotateToggle',
  ],
  'controlMirrorCapture': [
    'screenMirror',
    'screenshot',
    'screenRecord',
    'cameraTitle',
    'audioOnlyMirror',
  ],
};

/// 按实际按钮区域验证组成员、换行留白及文字完整性，兼容实心和描边状态。
void _expectQuickGroups(WidgetTester tester, AppLocalizations l10n) {
  final groupBounds = <Rect>[];
  for (final group in _quickGroups.entries) {
    final groupFinder = find.byKey(ValueKey(group.key));
    final bounds = tester.getRect(groupFinder);
    groupBounds.add(bounds);
    final title = find.descendant(
      of: groupFinder,
      matching: find.text(l10n.t(group.key)),
    );
    expect(title, findsOneWidget);
    final buttonBounds = <Rect>[];
    for (final key in group.value) {
      final label = find.descendant(
        of: groupFinder,
        matching: find.text(l10n.t(key)),
      );
      expect(label, findsOneWidget, reason: key);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(paragraph.didExceedMaxLines, isFalse, reason: key);
      final button = find.ancestor(
        of: label,
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      final rect = tester.getRect(button);
      expect(bounds.contains(rect.center), isTrue, reason: key);
      expect(
        rect.top,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
        reason: key,
      );
      expect(buttonBounds.any(rect.overlaps), isFalse, reason: key);
      buttonBounds.add(rect);
    }
  }
  for (var i = 1; i < groupBounds.length; i++) {
    expect(groupBounds[i].left, closeTo(groupBounds.first.left, 1));
    expect(groupBounds[i].top - groupBounds[i - 1].bottom, closeTo(12, 0.1));
  }
}

/// 同名「设置自定义值」均与各自输入框同行，点击后检查实际模拟 ADB 调用。
Future<void> _expectCustomInputs(
  WidgetTester tester,
  AppLocalizations l10n,
  _ControlAdb adb,
) async {
  final inputs = find.byType(TextField);
  final submit = find.widgetWithText(OutlinedButton, l10n.t('setCustomLabel'));
  expect(inputs, findsNWidgets(3));
  expect(submit, findsNWidgets(2));
  final examples = [
    ('1.15', ['settings', 'put', 'system', 'font_scale', '1.15']),
    ('800x1200', ['wm', 'size', '800x1200']),
  ];
  for (var i = 0; i < examples.length; i++) {
    final field = inputs.at(i);
    final button = submit.at(i);
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    final fieldRect = tester.getRect(field);
    final buttonRect = tester.getRect(button);
    expect(buttonRect.center.dy, closeTo(fieldRect.center.dy, 2));
    expect(buttonRect.left - fieldRect.right, inInclusiveRange(0, 16));
    await tester.enterText(field, examples[i].$1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(adb.commands.last, [_phone.id, ...examples[i].$2]);
  }
}

void main() {
  for (final (size, language, brightness) in [
    (const Size(1100, 780), 'zh', Brightness.light),
    (const Size(700, 400), 'en', Brightness.dark),
  ]) {
    testWidgets('Android 控制页分组、输入与电源滚动入口 $size $language', (tester) async {
      final l10n = AppLocalizations(Locale(language));
      final adb = await _openControl(
        tester,
        size: size,
        l10n: l10n,
        brightness: brightness,
      );
      for (final key in [
        'deviceActions',
        'deeplink',
        'layoutHelper',
        'systemSettings',
        'wifiPasswordTitle',
        'certManagerTitle',
        'powerTitle',
      ]) {
        expect(find.text(l10n.t(key)), findsWidgets, reason: key);
      }
      _expectQuickGroups(tester, l10n);
      final fontLabel = tester.getRect(find.text(l10n.t('fontScaleLabel')));
      final firstPreset = tester.getRect(
        find.widgetWithText(OutlinedButton, '0.80'),
      );
      if (size.width == 700) {
        expect(fontLabel.left, closeTo(firstPreset.left, 1));
        expect(fontLabel.bottom, lessThan(firstPreset.top));
      } else {
        expect(fontLabel.right, lessThan(firstPreset.left));
        expect(fontLabel.top, lessThan(firstPreset.bottom));
      }
      final inputButton = find.text(l10n.t('inputText'));
      await tester.ensureVisible(inputButton);
      await tester.tap(inputButton);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(l10n.t('cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await _expectCustomInputs(tester, l10n, adb);
      final rootHint = find.text(l10n.t('wifiPasswordNoRoot'));
      expect(
        tester.renderObject<RenderParagraph>(rootHint).didExceedMaxLines,
        isFalse,
      );
      final last = find.text(l10n.t('rebootSideloadAutoReboot'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(last.hitTestable(), findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(last).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Android 离线时保留设备操作分组并阻止点击', (tester) async {
    final l10n = AppLocalizations(const Locale('zh'));
    await _openControl(
      tester,
      size: const Size(700, 400),
      l10n: l10n,
      brightness: Brightness.light,
      online: false,
    );
    expect(find.text(l10n.t('offlineControlWarning')), findsOneWidget);
    final input = find.text(l10n.t('inputText'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(input));
    await tester.pumpAndSettle();
    expect(input.hitTestable(), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
