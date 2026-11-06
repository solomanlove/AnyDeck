import 'dart:async';

import 'package:any_deck/app/window/mirror/app_mirror_launch_coordinator.dart';
import 'package:any_deck/core/adb/adb_result.dart';
import 'package:any_deck/core/adb/adb_service.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/core/scrcpy/fusion_display_resize.dart';
import 'package:any_deck/core/scrcpy/fusion_mode_preference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _AdbFake extends AdbService {
  _AdbFake() : super(executable: 'adb');

  final commands = <List<String>>[];
  int? sdk = 35;
  String serial = 'PHONE-1';
  bool failMove = false;
  bool launcherAvailable = true;
  bool taskAvailable = true;

  @override
  Future<AdbResult> shellArgs(
    String deviceId,
    List<String> args, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    commands.add(args);
    if (args.contains('ro.build.version.sdk')) {
      return AdbResult(
        exitCode: sdk == null ? 1 : 0,
        stdout: sdk?.toString() ?? '',
        stderr: '',
      );
    }
    if (args.contains('ro.serialno') || args.contains('ro.boot.serialno')) {
      return AdbResult(exitCode: 0, stdout: serial, stderr: '');
    }
    if (args.contains('resolve-activity')) {
      return AdbResult(
        exitCode: 0,
        stdout: launcherAvailable
            ? 'priority=0 preferredOrder=0\ncom.example.gallery/.MainActivity\n'
            : 'No activity found\n',
        stderr: '',
      );
    }
    if (args.contains('list')) {
      return AdbResult(
        exitCode: 0,
        stdout: taskAvailable
            ? 'RootTask id=42 displayId=7\n'
                '  taskId=42: com.example.gallery/.MainActivity\n'
            : '',
        stderr: '',
      );
    }
    if (args.contains('move-stack') && failMove) {
      return const AdbResult(exitCode: 1, stdout: '', stderr: 'move failed');
    }
    return const AdbResult(exitCode: 0, stdout: 'Starting: Intent', stderr: '');
  }
}

class _StoreFake implements FusionModeStore {
  final values = <String, bool>{};

  @override
  Future<bool?> read(String key) async => values[key];

  @override
  Future<void> write(String key, bool enabled) async {
    values[key] = enabled;
  }
}

class _WindowsFake implements AppMirrorWindowGateway {
  final created = <Map<String, dynamic>>[];
  String? existing;
  int waitCount = 0;
  Completer<void>? createGate;

  @override
  Future<String?> focusFusion(
    String deviceId,
    String? physicalKey,
    String packageName,
  ) async => existing;

  @override
  Future<String> create(
    Map<String, dynamic> arguments,
    Size size,
    String title,
  ) async {
    if (createGate != null) await createGate!.future;
    created.add(arguments);
    return '${created.length}';
  }

  @override
  Future<void> waitForFusionFrame(String windowId) async {
    waitCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final phone = RegisteredDevice(
    id: 'usb-1',
    status: 'device',
    isOnline: true,
    serial: 'PHONE-1',
    sdkVersion: 34,
  );

  test('Android 14+ 默认开，显式关闭在 USB 和无线连接共用', () async {
    final adb = _AdbFake();
    final store = _StoreFake();
    final preference = FusionModePreference(adb, store: store);
    expect(
      (await preference.resolve('usb-1', device: phone)).state,
      FusionModeState.enabled,
    );
    await preference.setEnabled('PHONE-1', false);
    final wifi = RegisteredDevice(
      id: '192.168.1.2:5555',
      status: 'device',
      isOnline: true,
      serial: 'PHONE-1',
      sdkVersion: 34,
    );
    expect(
      (await preference.resolve(wifi.id, device: wifi)).state,
      FusionModeState.disabled,
    );
    expect(store.values, hasLength(1));
    expect(adb.commands, isEmpty);
  });

  test('低版本与无法识别身份均不会误开融合投屏', () async {
    final adb = _AdbFake()..serial = 'unknown';
    final preference = FusionModePreference(adb, store: _StoreFake());
    final oldPhone = RegisteredDevice(
      id: 'usb-old',
      status: 'device',
      isOnline: true,
      sdkVersion: 33,
    );
    expect(
      (await preference.resolve('usb-old', device: oldPhone)).state,
      FusionModeState.unsupported,
    );
    expect(
      (await preference.resolve('192.168.1.2:5555')).state,
      FusionModeState.unknown,
    );
    expect(
      adb.commands.where((args) => args.contains('ro.build.version.sdk')),
      hasLength(1),
    );
  });

  test('实际启动前重读 SDK，缓存过期时回退普通投屏', () async {
    final adb = _AdbFake()..sdk = 33;
    final preference = FusionModePreference(adb, store: _StoreFake());
    final status = await preference.resolve(
      'usb-1',
      device: phone,
      refreshSdk: true,
    );
    expect(status.state, FusionModeState.unsupported);
    expect(status.sdkVersion, 33);
  });

  test('融合、关闭后的 display 0、已有融合窗口复用走同一协调器', () async {
    final adb = _AdbFake();
    final store = _StoreFake();
    final preference = FusionModePreference(adb, store: store);
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      preference,
      windows: windows,
    );
    final request = AppMirrorLaunchRequest(
      deviceId: 'usb-1',
      packageName: 'com.example.gallery',
      appName: 'Gallery',
      mirrorTitleTemplate: 'Mirror - {name}',
      alwaysOnTop: true,
      device: phone,
      physicalResolution: '1080x2400/420dpi',
    );

    final fusion = await coordinator.open(request);
    expect(fusion.kind, AppMirrorLaunchKind.fusion);
    expect(windows.created.single['startApp'], 'com.example.gallery');
    expect(windows.created.single['newDisplay'], isNotNull);
    expect(windows.waitCount, 1);

    await preference.setEnabled('PHONE-1', false);
    windows.existing = '1';
    final reused = await coordinator.open(request);
    expect(reused.kind, AppMirrorLaunchKind.existingFusion);
    expect(windows.created, hasLength(1));

    windows.existing = null;
    final primary = await coordinator.open(request);
    expect(primary.kind, AppMirrorLaunchKind.primary);
    expect(windows.created.last['startApp'], isNull);
    expect(windows.created.last['newDisplay'], isNull);
    expect(windows.created.last['deviceName'], 'usb-1');
    expect(
      adb.commands.any(
        (args) => args.contains('move-stack') && args.last == '0',
      ),
      isTrue,
    );
    expect(
      adb.commands.any(
        (args) => args.contains('--display') && args.contains('0'),
      ),
      isTrue,
    );
    expect(
      adb.commands.any(
        (args) => args.contains('-n') &&
            args.contains('com.example.gallery/.MainActivity'),
      ),
      isTrue,
    );
  });

  test('同一应用的并发点击共享启动与首帧等待', () async {
    final adb = _AdbFake();
    final windows = _WindowsFake()..createGate = Completer<void>();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      FusionModePreference(adb, store: _StoreFake()),
      windows: windows,
    );
    const request = AppMirrorLaunchRequest(
      deviceId: 'usb-1',
      packageName: 'com.example.gallery',
      appName: 'Gallery',
      mirrorTitleTemplate: 'Mirror - {name}',
      alwaysOnTop: false,
    );
    final first = coordinator.open(request);
    final repeated = coordinator.open(request);
    expect(identical(first, repeated), isTrue);
    windows.createGate!.complete();
    final results = await Future.wait([first, repeated]);
    expect(results.map((result) => result.windowId), ['1', '1']);
    expect(windows.created, hasLength(1));
    expect(windows.waitCount, 1);
  });

  test('没有 LAUNCHER Activity 时不创建融合投屏窗口', () async {
    final adb = _AdbFake()
      ..launcherAvailable = false
      ..taskAvailable = false;
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      FusionModePreference(adb, store: _StoreFake()),
      windows: windows,
    );

    await expectLater(
      coordinator.open(
        const AppMirrorLaunchRequest(
          deviceId: 'usb-1',
          packageName: 'com.example.gallery',
          appName: 'Gallery',
          mirrorTitleTemplate: 'Mirror - {name}',
          alwaysOnTop: false,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(windows.created, isEmpty);
  });

  test('已有 Task 即使没有 LAUNCHER Activity 也允许迁移', () async {
    final adb = _AdbFake()..launcherAvailable = false;
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      FusionModePreference(adb, store: _StoreFake()),
      windows: windows,
    );

    final result = await coordinator.open(
      const AppMirrorLaunchRequest(
        deviceId: 'usb-1',
        packageName: 'com.example.gallery',
        appName: 'Gallery',
        mirrorTitleTemplate: 'Mirror - {name}',
        alwaysOnTop: false,
      ),
    );
    expect(result.kind, AppMirrorLaunchKind.fusion);
    expect(windows.created, hasLength(1));
    expect(
      adb.commands.where((args) => args.contains('resolve-activity')),
      isEmpty,
    );
  });

  test('主屏迁移失败时不创建普通投屏窗口', () async {
    final adb = _AdbFake()..failMove = true;
    final preference = FusionModePreference(adb, store: _StoreFake());
    await preference.setEnabled('PHONE-1', false);
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      preference,
      windows: windows,
    );
    await expectLater(
      coordinator.open(
        AppMirrorLaunchRequest(
          deviceId: 'usb-1',
          packageName: 'com.example.gallery',
          appName: 'Gallery',
          mirrorTitleTemplate: 'Mirror - {name}',
          alwaysOnTop: false,
          device: phone,
        ),
      ),
      throwsStateError,
    );
    expect(windows.created, isEmpty);
  });

  test('错误页回退保留物理身份，HarmonyOS 使用原平台启动', () async {
    final adb = _AdbFake();
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      FusionModePreference(adb, store: _StoreFake()),
      windows: windows,
      launchHarmonyApp: (deviceId, packageName) async {
        expect(deviceId, 'harmony:phone');
        expect(packageName, 'com.example.gallery');
      },
    );
    final harmony = RegisteredDevice(
      id: 'harmony:phone',
      status: 'device',
      isOnline: true,
      isHarmony: true,
    );
    final platform = await coordinator.open(
      AppMirrorLaunchRequest(
        deviceId: harmony.id,
        packageName: 'com.example.gallery',
        appName: 'Gallery',
        mirrorTitleTemplate: 'Mirror - {name}',
        alwaysOnTop: false,
        device: harmony,
      ),
    );
    expect(platform.kind, AppMirrorLaunchKind.primary);
    expect(windows.created.single['isHarmony'], isTrue);
    expect(adb.commands, isEmpty);

    final primary = await coordinator.open(
      const AppMirrorLaunchRequest(
        deviceId: '192.168.1.2:5555',
        packageName: 'com.example.gallery',
        appName: 'Gallery',
        mirrorTitleTemplate: 'Mirror - {name}',
        alwaysOnTop: false,
        physicalDeviceKey: 'PHONE-1',
        forcePrimary: true,
      ),
    );
    expect(primary.kind, AppMirrorLaunchKind.primary);
    expect(windows.created.last['physicalDeviceKey'], 'PHONE-1');
  });

  test('非法包名在进入平台 shell 之前拒绝', () async {
    final adb = _AdbFake();
    final windows = _WindowsFake();
    final coordinator = AppMirrorLaunchCoordinator(
      adb,
      FusionModePreference(adb, store: _StoreFake()),
      windows: windows,
    );
    await expectLater(
      coordinator.open(
        const AppMirrorLaunchRequest(
          deviceId: 'usb-1',
          packageName: 'com.example.gallery;reboot',
          appName: 'Gallery',
          mirrorTitleTemplate: 'Mirror - {name}',
          alwaysOnTop: false,
        ),
      ),
      throwsArgumentError,
    );
    expect(adb.commands, isEmpty);
    expect(windows.created, isEmpty);
  });

  test('融合副屏随窗口重排并保持逻辑高度', () {
    final resizer = FusionDisplayResizer();
    final portrait = resizer.requestFor(692, 800)!;
    expect(portrait.newDisplay, '1384x1600/197');
    expect(portrait.resizeMessage, [21, 0x05, 0x68, 0x06, 0x40]);
    expect(resizer.requestFor(692, 800), isNull);

    final landscape = resizer.requestFor(1600, 924)!;
    expect(landscape.newDisplay, '1600x924/114');
    expect(160 * portrait.height / portrait.densityDpi, closeTo(1300, 5));
    expect(160 * landscape.height / landscape.densityDpi, closeTo(1300, 5));
    resizer.retryLast();
    expect(resizer.requestFor(1600, 924)?.newDisplay, landscape.newDisplay);
  });

  test('连续缩放时尺寸与 density 按顺序更新，最终采用窄窗口 DPI', () async {
    final wide = FusionDisplayGeometry.fromViewport(1128, 780);
    final narrow = FusionDisplayGeometry.fromViewport(688, 780);
    final firstDensityStarted = Completer<void>();
    final releaseFirstDensity = Completer<void>();
    final operations = <String>[];
    var currentDpi = 0;
    final queue = FusionDisplayUpdateQueue(
      sendResize: (geometry) async {
        operations.add('resize:${geometry.densityDpi}');
        return true;
      },
      setDensity: (geometry) async {
        final dpi = geometry.densityDpi;
        operations.add('density:$dpi');
        if (dpi == wide.densityDpi) {
          firstDensityStarted.complete();
          await releaseFirstDensity.future;
        }
        currentDpi = dpi;
        return true;
      },
    );

    final first = queue.submit(wide);
    await firstDensityStarted.future;
    final second = queue.submit(narrow);
    expect(operations, ['resize:${wide.densityDpi}', 'density:${wide.densityDpi}']);

    releaseFirstDensity.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(operations, [
      'resize:${wide.densityDpi}',
      'density:${wide.densityDpi}',
      'resize:${narrow.densityDpi}',
      'density:${narrow.densityDpi}',
    ]);
    expect(currentDpi, narrow.densityDpi);
  });
}
