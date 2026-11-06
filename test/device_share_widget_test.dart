import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/device_share/device_share_service.dart';
import 'package:any_deck/core/device_share/joined_device_share.dart';
import 'package:any_deck/features/devices/widgets/device_share_dialog.dart';
import 'package:any_deck/features/devices/widgets/device_share_controls.dart';
import 'package:any_deck/features/devices/widgets/adb_wireless_controls.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_adb_service.dart';
import 'support/device_context_menu_fixture.dart';

class _Sharing extends DeviceShareService {
  _Sharing() : super(FakeAdbService());
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
      final android = find.byWidgetPredicate(
        (widget) =>
            widget is DeviceShareControls &&
            widget.device.id == deviceMenuAndroid.id,
      );
      final action = find.descendant(
        of: android,
        matching: find.byType(IconButton),
      );
      expect(action, findsOneWidget);
      expect(tester.widget<IconButton>(action).onPressed, isNotNull);
      for (final device in [deviceMenuIos, deviceMenuHarmony]) {
        final controls = find.byWidgetPredicate(
          (widget) =>
              widget is DeviceShareControls && widget.device.id == device.id,
        );
        expect(
          find.descendant(of: controls, matching: find.byType(IconButton)),
          findsNothing,
        );
      }
      await tester.tap(action);
      // 外层设备行同时支持 DoubleTap，等待 Gesture Arena 完成单击判定。
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
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
      await withDeviceMenu(
        tester,
        (fixture) async {
          final context = tester.element(
            find.byType(DeviceShareControls).first,
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
            find.textContaining(language == 'zh' ? '共享操作失败' : 'Sharing failed'),
            findsOneWidget,
          );
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(language == 'zh' ? '关闭' : 'Close').last);
          await tester.pumpAndSettle();
          await service.dispose();
        },
        language: language,
        brightness: brightness,
        sharing: service,
      );
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
      final controls = find.byType(AdbWirelessControls);
      expect(
        find.descendant(of: controls, matching: find.byType(IconButton)),
        findsNothing,
      );
      final l10n = AppLocalizations.of(
        tester.element(find.byType(DeviceShareControls).first),
      );
      expect(find.text(l10n.t('deviceShareSource')), findsOneWidget);
    }, devices: [shared]);
  });
}
