import 'dart:async';

import 'package:any_deck/app/settings/app_settings.dart';
import 'package:any_deck/app/settings/app_settings_controller.dart';
import 'package:any_deck/app/window/mirror/mirror_window_app.dart';
import 'package:any_deck/core/apps/adb_package.dart';
import 'package:any_deck/core/device_info/device_overview.dart';
import 'package:any_deck/core/logging/app_log_recorder.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/embedded_scrcpy_service.dart';
import 'package:any_deck/core/scrcpy/mirror_stream_health.dart';
import 'package:any_deck/core/scrcpy/mirror_transport_devices_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/mirror_transport_fakes.dart';

const _shared = '127.0.0.1:5559';

/// 保留真实窗口和投屏 Notifier，只替换设备、原生窗口及视频像素边界。
class _WindowMirrors extends TransportMirrors {
  @override
  Map<String, int>? getVideoSize(String deviceId) =>
      isActive(deviceId) ? const {'width': 1920, 'height': 1448} : null;

  @override
  int? getDecodedFrames(String deviceId) => isActive(deviceId) ? 30 : null;

  @override
  int? getVirtualDisplayId(String deviceId) => null;
}

/// 避免异步加载真实用户设置，固定测试窗口工具栏的展示方式。
class _Settings extends AppSettingsController {
  @override
  AppSettings build() => AppSettings(mirrorControlsAlwaysVisible: true);
}

/// 不读取真实设备历史，平台与在线状态由会话边界提供。
class _Registry extends DeviceRegistryNotifier {
  @override
  List<RegisteredDevice> build() => const [];
}

/// 保留窗口对应用列表的真实订阅，隔离磁盘与手机查询。
class _Packages extends PackagesNotifier {
  _Packages(super.deviceId);
  @override
  AsyncValue<List<AdbPackage>> build() => const AsyncData([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  const windowManager = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _WindowMirrors mirrors;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(windows, (call) async {
      if (call.method == 'getAllWindows') return <Object>[];
      if (call.method == 'getWindowDefinition') {
        return {'windowId': 'shared-mirror-test', 'windowArgument': ''};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(channels, (call) async => true);
    messenger.setMockMethodCallHandler(windowManager, (call) async {
      if (call.method == 'getSize') return {'width': 800.0, 'height': 600.0};
      if (call.method == 'getPosition') return {'x': 0.0, 'y': 0.0};
      if (call.method.startsWith('is')) return false;
      return null;
    });
    mirrors = _WindowMirrors();
    container = ProviderContainer(
      overrides: [
        windowIdProvider.overrideWithValue('shared-mirror-test'),
        appSettingsProvider.overrideWith(_Settings.new),
        adbServiceProvider.overrideWithValue(
          TransportAdb()..serials[_shared] = '',
        ),
        embeddedScrcpyServiceProvider.overrideWithValue(mirrors),
        deviceRegistryProvider.overrideWith(_Registry.new),
        deviceSdkVersionProvider.overrideWith((ref, deviceId) => 34),
        packagesProvider(_shared).overrideWith(() => _Packages(_shared)),
        deviceOverviewProvider.overrideWith(
          (ref, deviceId) =>
              Stream.value(DeviceOverview.fromJson({'name': 'Test phone'})),
        ),
        mirrorTransportDevicesProvider.overrideWith(
          (ref) => const Stream.empty(),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
    messenger.setMockMethodCallHandler(windowManager, null);
  });

  Future<void> openWindow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MirrorWindowApp(
          windowId: 'shared-mirror-test',
          argument: {'deviceId': _shared, 'deviceName': 'Test phone'},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(mirrors.starts, hasLength(1));
    expect(container.read(deviceOnlineProvider(_shared)), isTrue);
    mirrors.qualities[_shared] = const MirrorVideoQuality(
      maxSize: 1920,
      bitrate: 16000000,
    );
  }

  Future<void> congest(WidgetTester tester) async {
    mirrors.health[_shared] = const MirrorStreamHealth(videoLagMs: 500);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
  }

  testWidgets('共享手机在真实投屏窗口拥塞降档后恢复，关闭窗口释放新会话', (tester) async {
    await openWindow(tester);
    final logOffset = AppLogRecorder.instance.history.length;
    final gate = Completer<void>();
    mirrors.stopGates[_shared] = gate;
    // 原生 Texture/Server 清理会异步完成，必须让窗口观察到中间的空 Session。
    await congest(tester);
    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(mirrors.starts, hasLength(2));
    expect(mirrors.requestedQualities.last?.maxSize, 1280);
    expect(mirrors.requestedQualities.last?.bitrate, 4000000);
    expect(container.read(activeEmbeddedMirrorProvider(_shared)), isNotNull);
    expect(container.read(deviceOnlineProvider(_shared)), isTrue);
    expect(container.read(mirrorDisconnectedProvider(_shared)), 0);
    expect(
      AppLogRecorder.instance.history.skip(logOffset),
      contains(
        allOf(
          contains('mirror: stream_recovery_requested'),
          contains('video_lag_ms=500'),
          contains('bitrate=4000000'),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(mirrors.isActive(_shared), isFalse);
    expect(mirrors.events.last, 'stopped:$_shared');
  });

  testWidgets('真实投屏窗口在降档清理期间关闭，不重新启动已关闭的会话', (tester) async {
    await openWindow(tester);
    final gate = Completer<void>();
    mirrors.stopGates[_shared] = gate;
    await congest(tester);
    expect(mirrors.events, contains('stop:$_shared'));

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pump();
    await tester.pump();

    expect(mirrors.starts, hasLength(1));
    expect(mirrors.isActive(_shared), isFalse);
    expect(container.read(activeEmbeddedMirrorProvider(_shared)), isNull);
    expect(container.read(mirrorDisconnectedProvider(_shared)), 0);
    expect(tester.takeException(), isNull);
  });
}
