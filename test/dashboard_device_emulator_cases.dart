part of 'dashboard_device_responsive_test.dart';

/// 在同一个完整 Dashboard 测试环境验证列表和设备墙的模拟器入口。
void _testDeviceEmulatorActions() {
  for (final listMode in [false, true]) {
    final viewName = listMode ? '列表' : '设备墙';
    final emulator = find.byKey(
      ValueKey(
        listMode ? 'device-row-emulator-5554' : 'device-wall-emulator-5554',
      ),
    );
    Finder action(String label) =>
        find.descendant(of: emulator, matching: find.text(label));

    testWidgets('$viewName直接启动已确认的 AVD 并跟踪失败、重试和上线', (tester) async {
      final service = _WorkspaceEmulatorService();
      var connections = <String, DiscoveredDevice>{};
      final container = await _pumpEmulatorWorkspace(
        tester,
        listMode: listMode,
        service: service,
        connections: () => connections,
        avdName: 'Primary_AVD',
        confirmed: true,
      );
      await tester.tap(action('启动'));
      await tester.pump();
      await tester.pump();
      expect(_emulatorWorkspacePath(container), '/devices');
      expect(service.names, ['Primary_AVD']);
      final startingButton = find.ancestor(
        of: action('正在启动...'),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(startingButton).onPressed, isNull);

      service.exits.single.complete(
        const EmulatorExit(1, 'Missing system image'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Missing system image'), findsOneWidget);
      await tester.tap(action('启动'));
      await tester.pump();
      await tester.pump();
      expect(service.names, ['Primary_AVD', 'Primary_AVD']);

      connections = {
        'Primary_AVD': const DiscoveredDevice(
          id: 'emulator-5554',
          status: 'device',
        ),
      };
      container.invalidate(emulatorConnectionsProvider);
      (container.read(deviceRegistryProvider.notifier) as _Registry)
          .setEmulator(avdName: 'Primary_AVD', confirmed: true, online: true);
      await tester.pumpAndSettle();
      expect(action('投屏'), findsOneWidget);
      expect(_emulatorWorkspacePath(container), '/devices');
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    for (final name in [null, 'Inferred_AVD']) {
      testWidgets('$viewName身份未确认时进入模拟器管理（$name）', (tester) async {
        final service = _WorkspaceEmulatorService();
        final container = await _pumpEmulatorWorkspace(
          tester,
          listMode: listMode,
          service: service,
          avdName: name,
        );
        await tester.tap(action('启动'));
        await tester.pumpAndSettle();
        expect(_emulatorWorkspacePath(container), '/emulators');
        expect(service.names, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    for (final status in ['offline', 'unauthorized']) {
      testWidgets('$viewName已有 $status transport 时只显示连接诊断', (tester) async {
        final service = _WorkspaceEmulatorService();
        final container = await _pumpEmulatorWorkspace(
          tester,
          listMode: listMode,
          service: service,
          connections: () => {
            'Primary_AVD': DiscoveredDevice(
              id: 'emulator-5580',
              status: status,
            ),
          },
          avdName: 'Primary_AVD',
          confirmed: true,
        );
        await tester.tap(action('启动'));
        // 设备墙按钮在诊断关闭前保留进度动画，只推进对话框入场所需的帧。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_emulatorWorkspacePath(container), '/devices');
        expect(service.names, isEmpty);
        expect(find.text('ADB 连接诊断'), findsOneWidget);
        expect(
          find.textContaining(
            status == 'offline' ? 'ADB 离线' : 'ADB 未授权',
            findRichText: true,
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final portReused in [false, true]) {
    testWidgets('已确认 AVD 的旧端口${portReused ? '被其他 AVD 复用' : '当前归属待确认'}', (
      tester,
    ) async {
      final service = _WorkspaceEmulatorService();
      const transport = DiscoveredDevice(
        id: 'emulator-5554',
        status: 'offline',
      );
      await _pumpEmulatorWorkspace(
        tester,
        listMode: true,
        service: service,
        connections: () => {if (portReused) 'Different_AVD': transport},
        discovered: [transport],
        avdName: 'Primary_AVD',
        confirmed: true,
      );
      await tester.tap(find.text('启动'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      if (portReused) {
        expect(service.names, ['Primary_AVD']);
        service.exits.single.complete(const EmulatorExit(1, 'Test exit'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
      } else {
        expect(service.names, isEmpty);
        expect(find.text('ADB 连接诊断'), findsOneWidget);
        await tester.tap(find.text('关闭'));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

String _emulatorWorkspacePath(ProviderContainer container) =>
    container.read(appRouterProvider).routeInformationProvider.value.uri.path;

Future<ProviderContainer> _pumpEmulatorWorkspace(
  WidgetTester tester, {
  required bool listMode,
  required _WorkspaceEmulatorService service,
  required String? avdName,
  bool confirmed = false,
  Map<String, DiscoveredDevice> Function()? connections,
  List<DiscoveredDevice> discovered = const [],
}) async {
  tester.view.physicalSize = const Size(1200, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await _pumpDashboard(
    tester,
    emulatorService: service,
    emulatorConnections: connections,
    discovered: discovered,
  );
  (container.read(deviceRegistryProvider.notifier) as _Registry).setEmulator(
    avdName: avdName,
    confirmed: confirmed,
  );
  await tester.pumpAndSettle();
  if (listMode) {
    await tester.tap(find.byKey(const Key('deviceView-list')));
    await tester.pumpAndSettle();
  }
  return container;
}

/// 用可控退出结果驱动真实启动 Provider，避免测试启动本机 AVD。
class _WorkspaceEmulatorService extends EmulatorService {
  final names = <String>[];
  final exits = <Completer<EmulatorExit>>[];

  @override
  Future<EmulatorProcess> startEmulator(
    String avdName, {
    bool coldBoot = false,
  }) async {
    names.add(avdName);
    final exit = Completer<EmulatorExit>();
    exits.add(exit);
    return EmulatorProcess(exited: exit.future, output: () => '');
  }
}
