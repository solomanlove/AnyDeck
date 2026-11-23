import 'package:any_deck/core/airplay/airplay_server_state.dart';
import 'package:any_deck/core/ios/ios_connection_type.dart';
import 'package:any_deck/features/devices/widgets/device_wall_phone.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 通过设备墙的实际点击入口检查工作区路由，并记录桌面子窗口调用。
void main() {
  const airplay = AirPlaySessionData(
    id: 1,
    serverName: 'AnyDeck',
    rtspPort: 0,
    videoPort: 0,
    status: AirPlayServerStatus.mirroring,
  );
  for (final device in [
    deviceMenuTarget,
    deviceMenuHarmony,
    deviceMenuIos.copyWith(iosConnectionTypes: {IosConnectionType.network}),
  ]) {
    testWidgets('在线 ${device.id} 的按钮与预览进入该设备工作区', (tester) async {
      final language = device.isHarmony ? 'en' : 'zh';
      final label = language == 'zh' ? '进入工作区' : 'Open workspace';
      await withDeviceMenu(
        tester,
        (fixture) async {
          final messenger = tester.binding.defaultBinaryMessenger;
          const windows = MethodChannel('mixin.one/desktop_multi_window');
          final calls = <String>[];
          messenger.setMockMethodCallHandler(windows, (call) async {
            calls.add(call.method);
            return call.method == 'getAllWindows' ? <Object>[] : null;
          });
          addTearDown(() => messenger.setMockMethodCallHandler(windows, null));

          final card = find.byKey(ValueKey('device-wall-${device.id}'));
          final button = find.descendant(of: card, matching: find.text(label));
          final phone = find.descendant(
            of: card,
            matching: find.byType(DeviceWallPhone),
          );
          for (final target in [button, phone]) {
            expect(target.hitTestable(), findsOneWidget);
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(
              fixture.router.routeInformationProvider.value.uri.path,
              '/devices/${device.id}/overview',
            );
            expect(calls, isEmpty, reason: '进入工作区不应查找或创建投屏窗口');
            fixture.router.go('/devices');
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
        },
        devices: [deviceMenuAndroid, device],
        airplay: device.isIos ? airplay : null,
        language: language,
      );
    });
  }

  testWidgets('只有 AirPlay 会话的设备卡片保留投屏操作', (tester) async {
    await withDeviceMenu(
      tester,
      (fixture) async {
        final card = find.byKey(const ValueKey('device-wall-airplay-1'));
        expect(
          find.descendant(of: card, matching: find.text('投屏')).hitTestable(),
          findsOneWidget,
        );
      },
      devices: const [],
      airplay: airplay,
    );
  });
}
