import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/src/internals.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/harmony/hdc_service.dart';
import 'package:any_deck/core/ios/ios_command_service.dart';
import 'package:any_deck/core/ios/ios_mirror_service.dart';
import 'package:any_deck/core/layout_inspector/layout_inspector_service.dart';
import 'package:any_deck/core/layout_inspector/layout_node.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/layout/layout_hierarchy_tree.dart';
import 'package:any_deck/features/layout/layout_properties_table.dart';
import 'package:any_deck/features/screenshot/controller/screenshot_controller.dart';
import 'package:any_deck/features/screenshot/dashboard_screenshot_tab.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:any_deck/features/screenshot/widgets/screenshot_canvas.dart';

import 'fake_adb_service.dart';

const _mockAndroidDevice = AdbDevice(
  id: 'android_device_001', status: 'device', model: 'Pixel 7', product: 'panther', transportId: '1',
);
const _mockIosDevice = AdbDevice(
  id: 'ios_device_001', status: 'device', model: 'iPhone 14', product: 'iPhone14,7', transportId: '3', isIos: true,
);
const _mockHarmonyDevice = AdbDevice(
  id: 'harmony_device_001', status: 'device', model: 'Mate 60', product: 'ALN-AL00', transportId: '4', isHarmony: true,
);

Future<Uint8List> _createTestPng([int width = 100, int height = 100]) async {
  final pictureRecorder = ui.PictureRecorder();
  final canvas = Canvas(pictureRecorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = pictureRecorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

const _mockXml = '''<?xml version="1.0" encoding="UTF-8"?>
<hierarchy rotation="0">
  <node index="0" text="Home" class="android.widget.TextView" bounds="[0,0][400,200]" />
  <node index="1" text="Submit" class="android.widget.Button" bounds="[0,200][400,400]" />
</hierarchy>''';

class MockLayoutInspectorService extends LayoutInspectorService {
  MockLayoutInspectorService(super.adb, this.testPngBytes);

  int captureLayoutCallCount = 0;
  int captureScreenshotCallCount = 0;
  bool shouldFailLayout = false;
  final Uint8List testPngBytes;

  @override
  Future<(LayoutNode, String)> captureLayout(String deviceId) async {
    captureLayoutCallCount++;
    if (shouldFailLayout) {
      throw Exception('Failed to dump uiautomator');
    }
    return (parseLayoutXml(_mockXml)!, _mockXml);
  }

  @override
  Future<Uint8List> captureScreenshot(String deviceId) async {
    captureScreenshotCallCount++;
    return testPngBytes;
  }
}

class _TestSelectedDeviceNotifier extends SelectedDeviceNotifier {
  _TestSelectedDeviceNotifier(this.device);
  final AdbDevice? device;

  @override
  AdbDevice? build() => device;
}

class _TestDeviceRegistryNotifier extends DeviceRegistryNotifier {
  _TestDeviceRegistryNotifier(this.devices);
  final List<RegisteredDevice> devices;

  @override
  List<RegisteredDevice> build() => devices;
}

class _FixedToolTabNotifier extends ToolTabNotifier {
  _FixedToolTabNotifier(this.initialIndex);
  final int initialIndex;

  @override
  int build() => initialIndex;
}

class _TestAdbService extends FakeAdbService {
  _TestAdbService(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return bytes;
  }
}

class _TestIosCommandService extends IosCommandService {
  _TestIosCommandService(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List> captureScreenshot(String udid) async => bytes;
}

class _TestHdcService extends HdcService {
  _TestHdcService(this.bytes) : super(executable: 'hdc');
  final Uint8List bytes;

  @override
  Future<Uint8List> captureScreenshot(
    String deviceId, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    return bytes;
  }
}

Widget _wrapTestWidget(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Screenshot and Layout Inspector Merge Tests', () {
    late Uint8List cachedPng;
    late _TestAdbService fakeAdb;
    late _TestIosCommandService fakeIos;
    late _TestHdcService fakeHdc;
    late MockLayoutInspectorService mockInspector;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      cachedPng = await _createTestPng();
      fakeAdb = _TestAdbService(cachedPng);
      fakeIos = _TestIosCommandService(cachedPng);
      fakeHdc = _TestHdcService(cachedPng);
      mockInspector = MockLayoutInspectorService(fakeAdb, cachedPng);
    });

    testWidgets('Navigation rail has only "截图录屏", no independent "布局分析"', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapTestWidget(
          PrimaryRail(selectedDevice: _mockAndroidDevice),
          overrides: [
            adbServiceProvider.overrideWithValue(fakeAdb),
            layoutInspectorServiceProvider.overrideWithValue(mockInspector),
            devicesProvider.overrideWith((ref) => Stream.value([_mockAndroidDevice])),
            deviceRegistryProvider.overrideWith(
              () => _TestDeviceRegistryNotifier([
                RegisteredDevice(
                  id: _mockAndroidDevice.id,
                  status: _mockAndroidDevice.status,
                  model: _mockAndroidDevice.model,
                  product: _mockAndroidDevice.product,
                  transportId: _mockAndroidDevice.transportId,
                  isOnline: true,
                  serial: _mockAndroidDevice.id,
                ),
              ]),
            ),
            selectedDeviceProvider.overrideWith(
              () => _TestSelectedDeviceNotifier(_mockAndroidDevice),
            ),
            selectedToolTabProvider.overrideWith(
              () => _FixedToolTabNotifier(9),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // "截图录屏" 入口应该存在
      expect(find.text('截图录屏'), findsOneWidget);
      // 独立的 "布局分析" 侧边栏入口已完全移除
      expect(find.text('布局分析'), findsNothing);
    });

    test('Tab index 8 redirects to 9 in ToolTabNotifier', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(selectedToolTabProvider.notifier);
      expect(container.read(selectedToolTabProvider), -1);

      // 旧索引 8 请求归一化到 9
      notifier.select(8);
      expect(container.read(selectedToolTabProvider), 9);

      // 其他索引保持不变
      notifier.select(3);
      expect(container.read(selectedToolTabProvider), 3);

      notifier.select(9);
      expect(container.read(selectedToolTabProvider), 9);
    });

    testWidgets('Layout analysis toggle visibility per platform', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 1. Android 设备应显示布局分析开关
      await tester.pumpWidget(
        _wrapTestWidget(
          const DashboardScreenshotTab(device: _mockAndroidDevice),
          overrides: [
            deviceOnlineProvider(_mockAndroidDevice.id).overrideWithValue(true),
            adbServiceProvider.overrideWithValue(fakeAdb),
            iosCommandServiceProvider.overrideWithValue(fakeIos),
            hdcServiceProvider.overrideWithValue(fakeHdc),
            layoutInspectorServiceProvider.overrideWithValue(mockInspector),
            deviceRegistryProvider.overrideWith(
              () => _TestDeviceRegistryNotifier([
                RegisteredDevice(
                  id: _mockAndroidDevice.id,
                  status: 'device',
                  isOnline: true,
                  serial: _mockAndroidDevice.id,
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('布局分析'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsOneWidget);

      // 2. iOS 设备不显示布局分析开关
      await tester.pumpWidget(
        _wrapTestWidget(
          const DashboardScreenshotTab(device: _mockIosDevice),
          overrides: [
            deviceOnlineProvider(_mockIosDevice.id).overrideWithValue(true),
            adbServiceProvider.overrideWithValue(fakeAdb),
            iosCommandServiceProvider.overrideWithValue(fakeIos),
            hdcServiceProvider.overrideWithValue(fakeHdc),
            layoutInspectorServiceProvider.overrideWithValue(mockInspector),
            deviceRegistryProvider.overrideWith(
              () => _TestDeviceRegistryNotifier([
                RegisteredDevice(
                  id: _mockIosDevice.id,
                  status: 'device',
                  isOnline: true,
                  serial: _mockIosDevice.id,
                  isIos: true,
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('布局分析'), findsNothing);
      expect(find.byType(CupertinoSwitch), findsNothing);

      // 3. HarmonyOS 设备也不显示布局分析开关
      await tester.pumpWidget(
        _wrapTestWidget(
          const DashboardScreenshotTab(device: _mockHarmonyDevice),
          overrides: [
            deviceOnlineProvider(_mockHarmonyDevice.id).overrideWithValue(true),
            adbServiceProvider.overrideWithValue(fakeAdb),
            iosCommandServiceProvider.overrideWithValue(fakeIos),
            hdcServiceProvider.overrideWithValue(fakeHdc),
            layoutInspectorServiceProvider.overrideWithValue(mockInspector),
            deviceRegistryProvider.overrideWith(
              () => _TestDeviceRegistryNotifier([
                RegisteredDevice(
                  id: _mockHarmonyDevice.id,
                  status: 'device',
                  isOnline: true,
                  serial: _mockHarmonyDevice.id,
                  isHarmony: true,
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('布局分析'), findsNothing);
      expect(find.byType(CupertinoSwitch), findsNothing);
    });

    testWidgets('Toggling layout analysis opens side panels and closing collapses them', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        _wrapTestWidget(
          const DashboardScreenshotTab(device: _mockAndroidDevice),
          overrides: [
            deviceOnlineProvider(_mockAndroidDevice.id).overrideWithValue(true),
            adbServiceProvider.overrideWithValue(fakeAdb),
            iosCommandServiceProvider.overrideWithValue(fakeIos),
            hdcServiceProvider.overrideWithValue(fakeHdc),
            layoutInspectorServiceProvider.overrideWithValue(mockInspector),
            deviceRegistryProvider.overrideWith(
              () => _TestDeviceRegistryNotifier([
                RegisteredDevice(
                  id: _mockAndroidDevice.id,
                  status: 'device',
                  isOnline: true,
                  serial: _mockAndroidDevice.id,
                ),
              ]),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 默认普通模式：无树和属性面板，只有共享画布
      expect(find.byType(LayoutHierarchyTree), findsNothing);
      expect(find.byType(LayoutPropertiesTable), findsNothing);
      expect(find.byType(ScreenshotCanvas), findsOneWidget);

      // 点击开启布局分析开关
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      // 开启后：左侧树和右侧属性面板均展开，调用了布局转储
      expect(find.byType(LayoutHierarchyTree), findsOneWidget);
      expect(find.byType(LayoutPropertiesTable), findsOneWidget);
      expect(find.byType(ScreenshotCanvas), findsOneWidget);
      expect(mockInspector.captureLayoutCallCount, greaterThan(0));

      // 再次点击关闭布局分析
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // 关闭后：两侧面板收起，中央画布依然保留
      expect(find.byType(LayoutHierarchyTree), findsNothing);
      expect(find.byType(LayoutPropertiesTable), findsNothing);
      expect(find.byType(ScreenshotCanvas), findsOneWidget);
    });

    test('Screen recording phases disable layout analysis switch with tooltip', () {
      final container = ProviderContainer(
        overrides: [
          adbServiceProvider.overrideWithValue(fakeAdb),
          layoutInspectorServiceProvider.overrideWithValue(mockInspector),
        ],
      );
      addTearDown(container.dispose);

      // 1. 默认 idle 时可以开启布局分析
      var state = container.read(screenshotLayoutControllerProvider('dev1'));
      expect(state.canToggleLayoutAnalysis, isTrue);
      expect(state.cannotToggleReasonKey, isNull);

      // 2. starting 阶段禁用
      state = state.copyWith(recordPhase: ScreenRecordPhase.starting);
      expect(state.canToggleLayoutAnalysis, isFalse);
      expect(state.cannotToggleReasonKey, 'recordingStartingDisableLayout');

      // 3. recording 阶段禁用
      state = state.copyWith(recordPhase: ScreenRecordPhase.recording);
      expect(state.canToggleLayoutAnalysis, isFalse);
      expect(state.cannotToggleReasonKey, 'recordingDisableLayoutAnalysis');

      // 4. stopping 阶段禁用
      state = state.copyWith(recordPhase: ScreenRecordPhase.stopping);
      expect(state.canToggleLayoutAnalysis, isFalse);
      expect(state.cannotToggleReasonKey, 'recordingStoppingDisableLayout');

      // 5. saving 阶段禁用
      state = state.copyWith(recordPhase: ScreenRecordPhase.saving);
      expect(state.canToggleLayoutAnalysis, isFalse);
      expect(state.cannotToggleReasonKey, 'recordingSavingDisableLayout');

      // 6. idle 阶段恢复可用
      state = state.copyWith(recordPhase: ScreenRecordPhase.idle);
      expect(state.canToggleLayoutAnalysis, isTrue);
      expect(state.cannotToggleReasonKey, isNull);
    });

    testWidgets('Atomic refresh does not mix data on layout failure', (
      WidgetTester tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          adbServiceProvider.overrideWithValue(fakeAdb),
          layoutInspectorServiceProvider.overrideWithValue(mockInspector),
        ],
      );
      addTearDown(container.dispose);

      final controller =
          container.read(screenshotLayoutControllerProvider('dev1').notifier);

      // 1. 首次成功加载
      await controller.loadLayoutAndScreenshot();
      final firstState =
          container.read(screenshotLayoutControllerProvider('dev1'));
      expect(firstState.rootNode, isNotNull);
      expect(firstState.decodedImage, isNotNull);
      expect(firstState.error, isNull);

      // 2. 模拟布局转储失败
      mockInspector.shouldFailLayout = true;
      await controller.loadLayoutAndScreenshot();
      final secondState =
          container.read(screenshotLayoutControllerProvider('dev1'));

      // 必须保留上一份完整数据，不得替换为不匹配的孤立截图
      expect(secondState.rootNode, equals(firstState.rootNode));
      expect(secondState.decodedImage, equals(firstState.decodedImage));
      expect(secondState.error, contains('Failed to dump uiautomator'));
    });
  });
}
