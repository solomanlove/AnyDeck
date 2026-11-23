import 'dart:convert';

import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/features/devices/widgets/device_wall_phone.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 从设备墙验证投屏子窗口与主窗口设备工作区各自的入口和目标。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windows = MethodChannel('mixin.one/desktop_multi_window');
  const channels = MethodChannel('mixin.one/desktop_multi_window/channels');
  final created = <Map<String, dynamic>>[];
  var showCount = 0;
  const airplay = AirPlaySessionData(
    id: 1,
    serverName: 'AnyDeck',
    rtspPort: 0,
    videoPort: 0,
    status: AirPlayServerStatus.mirroring,
  );
  final wifiIos = deviceMenuIos.copyWith(
    iosConnectionTypes: {IosConnectionType.network},
  );

  setUp(() {
    created.clear();
    showCount = 0;
    messenger.setMockMethodCallHandler(windows, (call) async {
      // 已接收的 AirPlay 会话会自动开窗，点击卡片应再次显示同一窗口。
      if (call.method == 'getAllWindows') {
        return [
          for (final window in created)
            {'windowId': 'mirror-test', 'windowArgument': jsonEncode(window)},
        ];
      }
      if (call.method == 'window_show') showCount++;
      if (call.method == 'createWindow') {
        final args = (call.arguments as Map)['arguments'] as String;
        created.add(jsonDecode(args) as Map<String, dynamic>);
        return 'mirror-test';
      }
      return null;
    });
    // 确认测试窗口已就绪，让 AirPlay 的切源和显示流程完整结束。
    messenger.setMockMethodCallHandler(channels, (call) async => true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windows, null);
    messenger.setMockMethodCallHandler(channels, null);
  });

  for (final (device, session) in [
    (deviceMenuTarget, null),
    (wifiIos, airplay),
    (null, airplay),
  ]) {
    final deviceId = device?.id ?? 'airplay-${airplay.id}';
    testWidgets('点击 $deviceId 卡片的投屏按钮打开对应窗口并留在设备管理', (tester) async {
      await withDeviceMenu(
        tester,
        (fixture) async {
          final card = find.byKey(ValueKey('device-wall-$deviceId'));
          final button = find.descendant(of: card, matching: find.text('投屏'));
          final previousShows = showCount;
          expect(created, hasLength(session == null ? 0 : 1));
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(created, hasLength(1));
          if (session != null) expect(showCount, greaterThan(previousShows));
          expect(created.single['type'], 'mirror');
          expect(created.single['deviceId'], deviceId);
          expect(created.single['airplayHandle'], session?.id);
          expect(
            fixture.router.routeInformationProvider.value.uri.path,
            '/devices',
          );
          expect(tester.takeException(), isNull);
        },
        devices: [deviceMenuAndroid, ?device],
        airplay: session,
      );
    });
  }

  for (final device in [deviceMenuTarget, deviceMenuHarmony, wifiIos]) {
    testWidgets('点击 ${device.id} 的预览或名称进入工作区', (tester) async {
      final language = device.isHarmony ? 'en' : 'zh';
      final workspaceLabel = language == 'zh' ? '进入工作区' : 'Open workspace';
      await withDeviceMenu(
        tester,
        (fixture) async {
          final card = find.byKey(ValueKey('device-wall-${device.id}'));
          if (device.isIos) {
            // 已注册的网络 iPhone 可以管理，USB 与 AirPlay 均缺失时无法投屏。
            final button = find.descendant(of: card, matching: find.text('投屏'));
            expect(
              tester.getSemantics(button),
              isSemantics(isButton: true, isEnabled: false),
            );
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(
              fixture.router.routeInformationProvider.value.uri.path,
              '/devices',
            );
            expect(created, isEmpty);
          }
          final phone = find.descendant(
            of: card,
            matching: find.byType(DeviceWallPhone),
          );
          expect(
            tester.widget<DeviceWallPhone>(phone).semanticLabel,
            '$workspaceLabel ${device.displayName}',
          );
          final name = find.descendant(
            of: card,
            matching: find.text(device.displayName),
          );
          for (final target in [phone, name]) {
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(
              fixture.router.routeInformationProvider.value.uri.path,
              '/devices/${device.id}/overview',
            );
            expect(created, isEmpty);
            fixture.router.go('/devices');
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
        devices: [deviceMenuAndroid, device],
        language: language,
      );
    });
  }
}
