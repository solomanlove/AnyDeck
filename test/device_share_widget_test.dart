import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/device_share/device_share_store.dart';
import 'package:any_deck/core/device_share/joined_device_share.dart';
import 'package:any_deck/features/devices/widgets/device_share_dialog.dart';
import 'package:any_deck/features/devices/model/device_context_action.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/device_context_menu_fixture.dart';

class _Sharing extends DeviceShareService {
  _Sharing() : super(FakeAdbService(), store: MemoryDeviceShareStore());
  String? attemptedCode;
  @override
  Future<JoinedDeviceShare> join(String code) async {
    attemptedCode = code;
    throw const FormatException('Test expired invitation');
  }
}

void main() {
  testWidgets('Android 行提供共享入口，iOS 和 HarmonyOS 不出现入口', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await fixture.openMenu(tester, deviceMenuAndroid);
      final action = deviceMenuAction(DeviceContextAction.share);
      expect(action, findsOneWidget);
      expect(
        tester.widget<PopupMenuItem<DeviceContextAction>>(action).enabled,
        isTrue,
      );
      await fixture.closeMenu(tester);
      for (final device in [deviceMenuIos, deviceMenuHarmony]) {
        await fixture.openMenu(tester, device);
        expect(deviceMenuAction(DeviceContextAction.share), findsNothing);
        await fixture.closeMenu(tester);
      }
      await fixture.openMenu(tester, deviceMenuAndroid);
      await tester.tap(action);
      // 模态框打开期间底层设备保持 busy 动画，只推进转场，不等待动画清零。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/devices',
      );
      expect(find.byType(DeviceShareDialog), findsOneWidget);
      expect(find.text('设备甲').last, findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '开始共享'))
            .onPressed,
        isNull,
      );
      expect(find.text('未找到局域网地址，请连接网络后重新打开。'), findsOneWidget);
      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        '/devices',
      );
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
    });
  });

  for (final (language, brightness) in [
    ('zh', Brightness.light),
    ('en', Brightness.dark),
  ]) {
    testWidgets('共享弹窗支持 $language、主题和错误恢复', (tester) async {
      final service = _Sharing();
      // 先由 fixture 释放 Riverpod 流订阅，再关闭 service 的广播控制器。
      try {
        await withDeviceMenu(
          tester,
          (fixture) async {
            final context = tester.element(
              find.byKey(const ValueKey('device-wall-device-a')),
            );
            // 使用真实本地化上下文打开接收入口，不启动网络或原生平台服务。
            showDialog<void>(
              context: context,
              builder: (_) => const DeviceShareDialog(),
            );
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byType(TextField).last,
              'expired-share-code',
            );
            await tester.tap(
              find.widgetWithText(
                FilledButton,
                language == 'zh' ? '连接共享设备' : 'Connect shared device',
              ),
            );
            await tester.pumpAndSettle();
            expect(service.attemptedCode, 'expired-share-code');
            expect(
              find.textContaining(
                language == 'zh' ? '共享操作失败' : 'Sharing failed',
              ),
              findsOneWidget,
            );
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.tap(find.text(language == 'zh' ? '关闭' : 'Close').last);
            await tester.pumpAndSettle();
          },
          language: language,
          brightness: brightness,
          sharing: service,
        );
      } finally {
        final closing = service.dispose();
        // close 的微任务属于 Widget test 的 FakeAsync，先推进后再等待完成。
        await tester.pump();
        await closing;
      }
    });
  }

  testWidgets('共享设备不显示手机无线调试连接操作', (tester) async {
    const shared = RegisteredDevice(
      id: '127.0.0.1:42345',
      model: '共享测试手机',
      status: 'device',
      isOnline: true,
      product: 'anydeck_shared_device',
    );
    await withDeviceMenu(tester, (fixture) async {
      expect(shared.hasWifiDebuggingConnection, isFalse);
      await fixture.openMenu(tester, shared);
      expect(deviceMenuAction(DeviceContextAction.wireless), findsNothing);
      expect(deviceMenuAction(DeviceContextAction.share), findsNothing);
      await fixture.closeMenu(tester);
      expect(find.text(shared.displayName), findsOneWidget);
    }, devices: [shared]);
  });
}
