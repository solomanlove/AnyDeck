import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/widgets/device_connection_history.dart';
import 'package:any_deck/features/devices/widgets/device_info_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _port = 'emulator-5600';
final _start = DateTime(2026, 11, 25, 14, 5, 9);
final _end = _start.add(const Duration(minutes: 1, seconds: 10));

/// 在真实弹窗校验时间、历史区域以及断开后结束时间的刷新。
void main() {
  for (final scenario in [
    (
      locale: const Locale('zh'),
      title: '连接历史',
      start: '开始时间',
      end: '结束时间',
      duration: '时长',
      current: '当前连接',
      running: '进行中',
      unknown: '时间未记录',
      closedDuration: '1分10秒',
    ),
    (
      locale: const Locale('en'),
      title: 'Connection history',
      start: 'Started',
      end: 'Ended',
      duration: 'Duration',
      current: 'Current connection',
      running: 'In progress',
      unknown: 'Time not recorded',
      closedDuration: '1m 10s',
    ),
  ]) {
    testWidgets('编辑弹窗显示连接起止时间与时长 ${scenario.locale}', (tester) async {
      await tester.binding.setSurfaceSize(const Size(670, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final device = _device();
      final registry = _Registry(device);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRegistryProvider.overrideWith(() => registry)],
          child: _host(scenario.locale, DeviceInfoEditDialog(device: device)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Api36_16KB'), findsOneWidget);
      final history = find.text(scenario.title);
      expect(history, findsOneWidget);
      expect(
        tester.getTopLeft(history).dy,
        greaterThan(tester.getBottomLeft(find.byType(TextField).last).dy),
      );
      await tester.ensureVisible(find.text('emulator-5556'));
      await tester.pumpAndSettle();
      expect(
        find.text('${scenario.start}  2026-11-25 14:05:09'),
        findsOneWidget,
      );
      expect(find.text('${scenario.end}  ${scenario.running}'), findsOneWidget);
      expect(find.text('${scenario.end}  ${scenario.unknown}'), findsOneWidget);
      expect(find.text(scenario.current), findsOneWidget);

      registry.replace([
        _device(disconnectedAt: _end),
        device.copyWith(emulatorAvdName: 'Another_AVD'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('${scenario.end}  2026-11-25 14:06:19'), findsOneWidget);
      expect(
        find.text('${scenario.duration}  ${scenario.closedDuration}'),
        findsOneWidget,
      );
      expect(find.text(scenario.current), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (locale, tag, confirm, isHarmony) in [
    (const Locale('zh'), '模拟器', '确认', false),
    (const Locale('en'), 'Emulator', 'Confirm', true),
  ]) {
    testWidgets('编辑弹窗在标签标识字段自动填入模拟器标签 ${locale.languageCode}', (
      tester,
    ) async {
      final device = RegisteredDevice(
        id: isHarmony ? '127.0.0.1:5555' : _port,
        status: 'offline',
        isOnline: false,
        isHarmony: isHarmony,
        isHarmonyEmulator: isHarmony,
        tags: const ['QA'],
      );
      final registry = _Registry(device);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRegistryProvider.overrideWith(() => registry)],
          child: _host(locale, DeviceInfoEditDialog(device: device)),
        ),
      );
      await tester.pumpAndSettle();

      final field = find.byType(TextField).at(1);
      expect(tester.widget<TextField>(field).controller!.text, '$tag, QA');
      await tester.enterText(field, '$tag，QA, Lab');
      await tester.tap(find.text(confirm));
      await tester.pumpAndSettle();
      expect(registry.savedTags, ['QA', 'Lab']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('在线时长每秒刷新，断开后固定并停止计时', (tester) async {
    var now = _start.add(const Duration(seconds: 3));
    Future<void> show(RegisteredDevice device) => tester.pumpWidget(
      _host(
        const Locale('zh'),
        DeviceConnectionHistory(device: device, now: () => now),
      ),
    );
    await show(_device());
    expect(find.text('时长  3秒'), findsOneWidget);

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('时长  4秒'), findsOneWidget);

    await show(_device(disconnectedAt: now));
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('时长  4秒'), findsOneWidget);
    expect(find.text('当前连接'), findsNothing);
  });
}

Widget _host(Locale locale, Widget body) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('zh'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: ThemeData(
    brightness: locale.languageCode == 'en'
        ? Brightness.dark
        : Brightness.light,
  ),
  home: Scaffold(body: body),
);

RegisteredDevice _device({DateTime? disconnectedAt}) => RegisteredDevice(
  id: _port,
  model: 'Android Emulator',
  status: disconnectedAt == null ? 'device' : 'offline',
  isOnline: disconnectedAt == null,
  emulatorAvdName: 'Api36_16KB',
  connectionHistory: [
    (id: 'emulator-5556', connectedAt: null, disconnectedAt: null),
    (
      id: _port,
      connectedAt: _start.toUtc(),
      disconnectedAt: disconnectedAt?.toUtc(),
    ),
  ],
  connections: const [_port],
);

/// 用同一 Registry Provider 模拟弹窗打开期间的端口复用。
class _Registry extends DeviceRegistryNotifier {
  _Registry(this.device);

  final RegisteredDevice device;
  List<String>? savedTags;

  @override
  List<RegisteredDevice> build() => [device];

  void replace(List<RegisteredDevice> devices) => state = devices;

  @override
  Future<void> setAlias(String id, String alias) async {}

  @override
  Future<void> updateTags(String id, List<String> tags) async {
    savedTags = tags;
  }

  @override
  Future<void> updateRemark(String id, String remark) async {}
}
