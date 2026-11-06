import 'dart:async';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

const _device = DiscoveredDevice(id: 'menu-device', status: 'device');
const _first = AdbPackage(name: 'com.example.first', label: '应用甲');
const _second = AdbPackage(name: 'com.example.second', label: '应用乙');
const _success = AdbResult(exitCode: 0, stdout: 'Success', stderr: '');

/// 记录真实服务生成的命令，禁止 Widget test 访问设备。
class _RecordingAdb extends FakeAdbService {
  final commands = <List<String>>[];
  Completer<AdbResult>? pending;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add([deviceId, ...args]);
    return pending?.future ?? _success;
  }
}

/// 固定应用快照并记录单包刷新，区分菜单打开与显式操作。
class _Packages extends PackagesNotifier {
  _Packages(this.items) : super(_device.id);

  final List<AdbPackage> items;
  final refreshed = <String>[];

  @override
  AsyncValue<List<AdbPackage>> build() => AsyncData(items);

  @override
  Future<void> refreshSinglePackage(String packageName) async {
    refreshed.add(packageName);
  }
}

class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

class _Online extends Notifier<bool> {
  @override
  bool build() => true;

  void disconnect() => state = false;
}

final _onlineProvider = NotifierProvider<_Online, bool>(_Online.new);

/// 仅挂载应用页；设备发现、应用刷新和命令均在测试内隔离。
Future<(ProviderContainer, _RecordingAdb, _Packages)> _mount(
  WidgetTester tester, {
  bool enabled = true,
  bool online = true,
  bool harmony = false,
  bool fusion = false,
  Brightness brightness = Brightness.light,
  String language = 'zh',
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final adb = _RecordingAdb();
  final packages = _Packages([
    _first,
    AdbPackage(name: _second.name, label: _second.label, enabled: enabled),
  ]);
  final container = ProviderContainer(
    overrides: [
      adbServiceProvider.overrideWithValue(adb),
      appManagementServiceProvider.overrideWithValue(AppManagementService(adb)),
      deviceRegistryProvider.overrideWith(_Registry.new),
      deviceOnlineProvider(
        _device.id,
      ).overrideWith((ref) => ref.watch(_onlineProvider)),
      packagesProvider(_device.id).overrideWith(() => packages),
      deviceFusionModeProvider(_device.id).overrideWith(
        (ref) async => FusionModeStatus(
          fusion ? FusionModeState.enabled : FusionModeState.unsupported,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (!online) container.read(_onlineProvider.notifier).disconnect();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        theme: buildAppTheme(brightness),
        home: Scaffold(
          body: AppsTab(
            device: DiscoveredDevice(
              id: _device.id,
              status: 'device',
              isHarmony: harmony,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, adb, packages);
}

Future<void> _rightClick(WidgetTester tester, String label) async {
  await tester.tap(
    find.text(label).first,
    buttons: kSecondaryButton,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('列表右键展示全部原操作，关闭后不再出现顶部工具栏', (tester) async {
    final (container, adb, packages) = await _mount(tester);
    final headerTop = tester.getTopLeft(find.textContaining('共 2/2 个应用')).dy;
    expect(find.byTooltip('应用详情'), findsNothing);
    await _rightClick(tester, _second.label!);
    for (final label in [
      '应用详情',
      '权限管理',
      '撤销所有权限',
      '打开手机应用信息',
      '启动',
      '普通投屏',
      '强停',
      '安装路径',
      '清除数据',
      '备份应用数据',
      '恢复应用数据',
      '冻结',
      '刷新该应用',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      findsNWidgets(13),
    );
    expect(adb.commands, isEmpty);
    expect(packages.refreshed, isEmpty);
    expect(container.read(selectedAppPackageProvider), isNull);
    await tester.tapAt(const Offset(20, 750));
    await tester.pumpAndSettle();
    expect(find.text('撤销所有权限'), findsNothing);
    expect(find.byTooltip('应用详情'), findsNothing);
    expect(find.byTooltip('刷新该应用'), findsNothing);
    expect(tester.getTopLeft(find.textContaining('共 2/2 个应用')).dy, headerTop);
  });

  testWidgets('已勾选其他应用时，右键启动只作用于当前目标', (tester) async {
    final (_, adb, _) = await _mount(tester);
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    await _rightClick(tester, _second.label!);
    await _choose(tester, '启动');
    expect(adb.commands, [
      [_device.id, 'monkey', '-p', _second.name, '1'],
    ]);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isFalse);
    expect(find.byTooltip('应用详情'), findsNothing);
  });

  testWidgets('清除数据取消不执行，确认后仅清除右键应用', (tester) async {
    final (_, adb, _) = await _mount(tester);
    await _rightClick(tester, _second.label!);
    await _choose(tester, '清除数据');
    expect(find.text('确定清除 ${_second.name} 的数据？'), findsOneWidget);
    await _choose(tester, '取消');
    expect(adb.commands, isEmpty);
    await _rightClick(tester, _second.label!);
    await _choose(tester, '清除数据');
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(adb.commands, [
      [_device.id, 'pm', 'clear', _second.name],
    ]);
  });

  for (final enabled in [true, false]) {
    testWidgets('根据启用状态展示并执行${enabled ? '冻结' : '解冻'}', (tester) async {
      final (_, adb, packages) = await _mount(tester, enabled: enabled);
      await _rightClick(tester, _second.label!);
      expect(find.text(enabled ? '解冻' : '冻结'), findsNothing);
      await _choose(tester, enabled ? '冻结' : '解冻');
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      expect(adb.commands, [
        [
          _device.id,
          ...(enabled
              ? ['pm', 'disable-user', '--user', '0', _second.name]
              : ['pm', 'enable', _second.name]),
        ],
      ]);
      expect(packages.refreshed, [_second.name]);
    });
  }

  testWidgets('离线菜单禁用；打开菜单后断线也不会发送命令', (tester) async {
    final (container, adb, _) = await _mount(tester);
    await _rightClick(tester, _second.label!);
    container.read(_onlineProvider.notifier).disconnect();
    await tester.pumpAndSettle();
    await _choose(tester, '启动');
    expect(adb.commands, isEmpty);
    await _rightClick(tester, _second.label!);
    final entries = tester.widgetList<PopupMenuItem>(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem),
    );
    expect(entries, hasLength(13));
    expect(entries.every((entry) => !entry.enabled), isTrue);
  });

  testWidgets('刷新菜单仅刷新目标应用，打开菜单不自动读取详情', (tester) async {
    final (_, adb, packages) = await _mount(tester);
    await _rightClick(tester, _second.label!);
    expect(packages.refreshed, isEmpty);
    await _choose(tester, '刷新该应用');
    expect(packages.refreshed, [_second.name]);
    expect(adb.commands, isEmpty);
  });

  testWidgets('确认弹窗期间断线，确认后仍不执行清除数据', (tester) async {
    final (container, adb, _) = await _mount(tester);
    await _rightClick(tester, _second.label!);
    await _choose(tester, '清除数据');
    container.read(_onlineProvider.notifier).disconnect();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    expect(adb.commands, isEmpty);
  });

  testWidgets('执行期间重复右键不叠加菜单，完成后可再次操作', (tester) async {
    final (_, adb, _) = await _mount(tester);
    adb.pending = Completer<AdbResult>();
    await _rightClick(tester, _second.label!);
    await _choose(tester, '启动');
    await _rightClick(tester, _first.label!);
    expect(find.text('强停'), findsNothing);
    expect(adb.commands, hasLength(1));
    adb.pending!.complete(_success);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await _rightClick(tester, _first.label!);
    expect(find.text('强停'), findsOneWidget);
  });

  testWidgets('网格右键支持英文暗色菜单与融合投屏动态文案', (tester) async {
    final (_, adb, _) = await _mount(
      tester,
      language: 'en',
      brightness: Brightness.dark,
      fusion: true,
    );
    await tester.tap(find.byKey(const Key('appsGridViewButton')));
    await tester.pumpAndSettle();
    await _rightClick(tester, _second.label!);
    expect(find.text('App details'), findsOneWidget);
    expect(find.text('Fusion mirroring'), findsNWidgets(2));
    expect(find.text('Back up app data'), findsOneWidget);
    await _choose(tester, 'Force stop');
    expect(adb.commands, [
      [_device.id, 'am', 'force-stop', _second.name],
    ]);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('App details'), findsNothing);
  });

  testWidgets('HarmonyOS 右键继续展示平台支持的操作', (tester) async {
    await _mount(tester, harmony: true);
    await _rightClick(tester, _second.label!);
    expect(find.text('清除缓存'), findsOneWidget);
    expect(find.text('卸载'), findsOneWidget);
    expect(find.text('权限管理'), findsNothing);
    expect(find.text('备份应用数据'), findsNothing);
  });
}
