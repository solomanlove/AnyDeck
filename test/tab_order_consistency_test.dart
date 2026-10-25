import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/src/internals.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/adb/adb_device.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/dashboard_screen.dart';

import 'fake_adb_service.dart';

const _mockAndroidDevice = AdbDevice(
  id: 'android_001',
  status: 'device',
  model: 'Pixel 7',
  product: 'panther',
  transportId: '1',
);

const _mockHarmonyDevice = AdbDevice(
  id: 'harmony_001',
  status: 'device',
  model: 'Mate 60',
  product: 'ALN-AL00',
  transportId: '2',
  isHarmony: true,
);

class _TestDeviceRegistryNotifier extends DeviceRegistryNotifier {
  _TestDeviceRegistryNotifier(this._initial);
  final List<RegisteredDevice> _initial;
  @override
  List<RegisteredDevice> build() => _initial;
}

class _TestSelectedDeviceNotifier extends SelectedDeviceNotifier {
  _TestSelectedDeviceNotifier(this._device);
  final AdbDevice? _device;
  @override
  AdbDevice? build() => _device;
}

class _FixedToolTabNotifier extends ToolTabNotifier {
  _FixedToolTabNotifier(this._tab);
  final int _tab;
  @override
  int build() => _tab;
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Tab Order Consistency Tests (Android vs HarmonyOS)', () {
    testWidgets('HarmonyOS tab order matches Android tab order for all shared tabs', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeAdb = FakeAdbService();

      // 1. 渲染 Android 设备侧边栏
      await tester.pumpWidget(
        _wrapTestWidget(
          PrimaryRail(selectedDevice: _mockAndroidDevice),
          overrides: [
            adbServiceProvider.overrideWithValue(fakeAdb),
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
              () => _FixedToolTabNotifier(0),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final androidTooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((w) => w.message)
          .whereType<String>()
          .skip(1)
          .toList();

      // 验证 Android 工具列表前几个按顺序为：主页、控制、应用、进程、文件、日志、终端调试
      final androidAppsIndex = androidTooltips.indexOf('应用');
      final androidProcessesIndex = androidTooltips.indexOf('进程');
      final androidFilesIndex = androidTooltips.indexOf('文件');

      expect(androidAppsIndex != -1, isTrue);
      expect(androidProcessesIndex != -1, isTrue);
      expect(androidFilesIndex != -1, isTrue);
      expect(androidProcessesIndex, equals(androidAppsIndex + 1),
          reason: 'Android 端 进程 应紧随 应用');
      expect(androidFilesIndex, equals(androidProcessesIndex + 1),
          reason: 'Android 端 文件 应紧随 进程');

      // 2. 渲染 HarmonyOS 设备侧边栏
      await tester.pumpWidget(
        _wrapTestWidget(
          PrimaryRail(selectedDevice: _mockHarmonyDevice),
          overrides: [
            adbServiceProvider.overrideWithValue(fakeAdb),
            devicesProvider.overrideWith((ref) => Stream.value([_mockHarmonyDevice])),
            deviceRegistryProvider.overrideWith(
              () => _TestDeviceRegistryNotifier([
                RegisteredDevice(
                  id: _mockHarmonyDevice.id,
                  status: _mockHarmonyDevice.status,
                  model: _mockHarmonyDevice.model,
                  product: _mockHarmonyDevice.product,
                  transportId: _mockHarmonyDevice.transportId,
                  isOnline: true,
                  isHarmony: true,
                  serial: _mockHarmonyDevice.id,
                ),
              ]),
            ),
            selectedDeviceProvider.overrideWith(
              () => _TestSelectedDeviceNotifier(_mockHarmonyDevice),
            ),
            selectedToolTabProvider.overrideWith(
              () => _FixedToolTabNotifier(0),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final harmonyTooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((w) => w.message)
          .whereType<String>()
          .skip(1)
          .toList();

      // 验证 HarmonyOS 端 进程 也紧随 应用，且在 文件 之前
      final harmonyAppsIndex = harmonyTooltips.indexOf('应用');
      final harmonyProcessesIndex = harmonyTooltips.indexOf('进程');
      final harmonyFilesIndex = harmonyTooltips.indexOf('文件');

      expect(harmonyAppsIndex != -1, isTrue);
      expect(harmonyProcessesIndex != -1, isTrue);
      expect(harmonyFilesIndex != -1, isTrue);
      expect(harmonyProcessesIndex, equals(harmonyAppsIndex + 1),
          reason: 'HarmonyOS 端 进程 应紧随 应用');
      expect(harmonyFilesIndex, equals(harmonyProcessesIndex + 1),
          reason: 'HarmonyOS 端 文件 应紧随 进程');

      // 3. 验证 HarmonyOS 所包含的所有共享工具在 Android 中的相对顺序完全一致
      final sharedInAndroid =
          androidTooltips.where((item) => harmonyTooltips.contains(item)).toList();
      expect(harmonyTooltips, equals(sharedInAndroid),
          reason: '鸿蒙的所有工具项顺序应与安卓完全一致');
    });
  });
}
