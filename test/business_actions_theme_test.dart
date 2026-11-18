import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/adb_environment_service.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/apps/adb_package_detail.dart';
import 'package:any_deck/core/apps/app_management_service.dart';
import 'package:any_deck/core/environment/connection_environment_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:any_deck/features/apps/controller/app_favorites_controller.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/developer/widget/developer_connection_environment_card.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_adb_service.dart';

const _device = DiscoveredDevice(id: 'business-theme', status: 'device');

/// 环境检测只记录调用，禁止主题测试访问 CLI。
class _Environment extends ConnectionEnvironmentNotifier {
  int checks = 0;

  @override
  Future<Map<TargetPlatformType, PlatformEnvironmentInfo>> checkAll() async {
    checks++;
    return state;
  }
}

class _Adb extends AdbEnvironmentNotifier {
  @override
  AdbEnvironmentInfo build() => const AdbEnvironmentInfo(
    status: AdbEnvironmentStatus.ready,
    version: 'test',
    adbPath: '/test/adb',
  );

  @override
  Future<AdbEnvironmentInfo> check() async => state;
}

/// 固定应用与组件快照，换主题时不重新查询设备。
class _Apps extends AppManagementService {
  _Apps() : super(FakeAdbService());

  int detailRequests = 0;

  @override
  Future<AdbPackageDetail> getPackageDetailedInfo(
    String deviceId,
    String packageName,
  ) async {
    detailRequests++;
    return AdbPackageDetail.fromJson({'packageName': packageName});
  }
}

class _Packages extends PackagesNotifier {
  _Packages(this.package) : super(_device.id);

  final AdbPackage package;

  @override
  AsyncValue<List<AdbPackage>> build() => AsyncData([package]);
}

class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => [];
}

/// 收藏状态仅存于内存，保留真实点击回调并禁止写入 Preference。
class _Favorites extends AppFavoritesNotifier {
  @override
  Future<Set<String>> build() async => {};

  @override
  Future<void> toggle(String packageName) async {
    final updated = {...?state.value};
    if (!updated.add(packageName)) updated.remove(packageName);
    state = AsyncData(updated);
  }
}

/// 保留实际页面子树，只更新主题以验证运行中的配色与页面状态。
Widget _app(
  ProviderContainer container,
  Brightness brightness,
  ValueNotifier<AppThemeColor> color,
  Widget child,
) => UncontrolledProviderScope(
  container: container,
  child: ValueListenableBuilder<AppThemeColor>(
    valueListenable: color,
    child: child,
    builder: (context, selected, child) => MaterialApp(
      theme: buildAppTheme(brightness, themeColor: selected),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: child),
    ),
  ),
);

/// 检查真实按钮的文字与 Material 边框，避免只验证样式参数。
void _expectGuideButtons(WidgetTester tester, Color primary) {
  for (final label in ['鸿蒙 HDC 引导测试', 'iOS 引导测试', 'ADB 缺失弹窗测试']) {
    final text = find.text(label);
    final button = find.ancestor(
      of: text,
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
    expect(DefaultTextStyle.of(tester.element(text)).style.color, primary);
    final material = tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)),
    );
    expect((material.shape! as OutlinedBorder).side.color, primary);
  }
}

/// 普通操作的图标及淡背景统一跟随主题，危险操作继续使用语义色。
void _expectAction(WidgetTester tester, String title, Color color) {
  final card = find.ancestor(of: find.text(title), matching: find.byType(Card));
  expect(card, findsOneWidget);
  final icon = tester.widget<Icon>(
    find.descendant(of: card, matching: find.byType(Icon)),
  );
  expect(icon.color, color, reason: title);
  final background = tester.widget<Container>(
    find.descendant(of: card, matching: find.byType(Container)),
  );
  expect(
    (background.decoration! as BoxDecoration).color,
    color.withValues(alpha: 0.1),
    reason: title,
  );
  expect(
    tester
        .widget<InkWell>(
          find.descendant(of: card, matching: find.byType(InkWell)),
        )
        .onTap,
    isNotNull,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 空路径使与配色无关的数据库检测安全回退，不访问原生服务或磁盘。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  for (final brightness in Brightness.values) {
    testWidgets('应用收藏选中态实时跟随主题且保留收藏状态 $brightness', (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final color = ValueNotifier(AppThemeColor.blue);
      const package = AdbPackage(name: 'com.example.favorite', label: '收藏主题测试');
      final container = ProviderContainer(
        overrides: [
          appManagementServiceProvider.overrideWithValue(_Apps()),
          deviceRegistryProvider.overrideWith(_Registry.new),
          deviceOnlineProvider(_device.id).overrideWith((ref) => true),
          packagesProvider(_device.id).overrideWith(() => _Packages(package)),
          appFavoritesProvider.overrideWith(_Favorites.new),
          deviceFusionModeProvider(_device.id).overrideWith(
            (ref) async => const FusionModeStatus(FusionModeState.unsupported),
          ),
        ],
      );
      addTearDown(color.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _app(container, brightness, color, const AppsTab(device: _device)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.star));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.star_fill)).color,
        AppThemeColor.blue.color,
      );
      color.value = AppThemeColor.purple;
      await tester.pumpAndSettle();
      expect(
        tester.widget<Icon>(find.byIcon(CupertinoIcons.star_fill)).color,
        AppThemeColor.purple.color,
      );
      expect(container.read(appFavoritesProvider).value, {package.name});
      await tester.tap(find.byIcon(CupertinoIcons.star_fill));
      await tester.pumpAndSettle();
      expect(container.read(appFavoritesProvider).value, isEmpty);
      expect(find.byIcon(CupertinoIcons.star), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('开发者三平台操作实时跟随主题且保留检测功能 $brightness', (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final color = ValueNotifier(AppThemeColor.blue);
      final container = ProviderContainer(
        overrides: [
          connectionEnvironmentProvider.overrideWith(_Environment.new),
          adbEnvironmentProvider.overrideWith(_Adb.new),
        ],
      );
      addTearDown(color.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _app(
          container,
          brightness,
          color,
          const SingleChildScrollView(
            child: DeveloperConnectionEnvironmentCard(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final environment =
          container.read(connectionEnvironmentProvider.notifier)
              as _Environment;
      expect(environment.checks, 1);
      _expectGuideButtons(tester, AppThemeColor.blue.color);
      color.value = AppThemeColor.purple;
      await tester.pumpAndSettle();
      _expectGuideButtons(tester, AppThemeColor.purple.color);
      expect(environment.checks, 1);
      await tester.tap(find.text('重新检测全部'));
      await tester.pumpAndSettle();
      expect(environment.checks, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final enabled in [true, false]) {
      testWidgets('应用详情普通操作实时跟随主题并保留页面状态 $brightness enabled=$enabled', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1440, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final color = ValueNotifier(AppThemeColor.blue);
        final service = _Apps();
        final package = AdbPackage(
          name: 'com.example.theme',
          label: '主题测试应用',
          apkPath: '/test/theme.apk',
          enabled: enabled,
        );
        final container = ProviderContainer(
          overrides: [
            appManagementServiceProvider.overrideWithValue(service),
            deviceRegistryProvider.overrideWith(_Registry.new),
            deviceOnlineProvider(_device.id).overrideWith((ref) => true),
            packagesProvider(_device.id).overrideWith(() => _Packages(package)),
            deviceFusionModeProvider(_device.id).overrideWith(
              (ref) async =>
                  const FusionModeStatus(FusionModeState.unsupported),
            ),
          ],
        );
        addTearDown(color.dispose);
        addTearDown(container.dispose);
        container.read(selectedAppPackageProvider.notifier).state =
            package.name;
        await tester.pumpWidget(
          _app(container, brightness, color, const AppsTab(device: _device)),
        );
        await tester.pumpAndSettle();

        void expectActions(AppThemeColor selected) {
          for (final title in [
            '启动应用',
            enabled ? '冻结应用' : '解冻应用',
            '普通投屏',
            '权限管理',
            '系统设置',
            '导出 APK',
            '备份数据',
            '恢复数据',
          ]) {
            _expectAction(tester, title, selected.color);
          }
          for (final entry in {
            '强行停止': const Color(0xFFE53935),
            '清除数据': const Color(0xFFFB8C00),
            '重置权限': const Color(0xFFD81B60),
            '卸载应用': const Color(0xFFE53935),
          }.entries) {
            _expectAction(tester, entry.key, entry.value);
          }
        }

        expectActions(AppThemeColor.blue);
        await tester.tap(find.text('原生库 (0)'));
        await tester.pumpAndSettle();
        final controller = DefaultTabController.of(
          tester.element(find.byType(TabBar)),
        );
        expect(controller.index, 1);
        color.value = AppThemeColor.purple;
        await tester.pumpAndSettle();
        expect(
          DefaultTabController.of(tester.element(find.byType(TabBar))),
          same(controller),
        );
        expect(controller.index, 1);
        expect(service.detailRequests, 1);
        expect(container.read(selectedAppPackageProvider), package.name);
        await tester.tap(find.text('功能操作'));
        await tester.pumpAndSettle();
        expectActions(AppThemeColor.purple);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
