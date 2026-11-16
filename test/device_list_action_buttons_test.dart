import 'package:any_deck/app/theme/app_theme_sizes.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/widgets/device_info_edit_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 从真实设备行查找操作按钮，覆盖嵌套的共享与无线按钮组件。
Finder _rowButtons(RegisteredDevice device) => find.descendant(
  of: find.ancestor(
    of: find.text(device.displayName),
    matching: find.byWidgetPredicate(
      (widget) => widget is InkWell && widget.onDoubleTap != null,
    ),
  ),
  matching: find.byType(IconButton),
);

void main() {
  final networkDevice = deviceMenuTarget.copyWith(
    connections: ['192.168.1.20:5555'],
  );
  final harmonyDevice = deviceMenuHarmony.copyWith(
    connections: ['192.168.1.21:5555'],
  );
  final iosDevice = deviceMenuIos.copyWith(ipAddress: '192.168.1.22');
  const emulator = RegisteredDevice(
    id: 'emulator-5554',
    model: '离线模拟器',
    status: 'offline',
    isOnline: false,
  );
  final expectedIcons = {
    deviceMenuAndroid: [
      Icons.share_outlined,
      CupertinoIcons.tv,
      CupertinoIcons.link,
      CupertinoIcons.pencil,
    ],
    networkDevice: [
      Icons.share_outlined,
      CupertinoIcons.tv,
      CupertinoIcons.bolt_slash,
      CupertinoIcons.pencil,
    ],
    deviceMenuOffline: [
      Icons.share_outlined,
      CupertinoIcons.link,
      CupertinoIcons.pencil,
    ],
    harmonyDevice: [
      CupertinoIcons.tv,
      CupertinoIcons.bolt_slash,
      CupertinoIcons.pencil,
    ],
    iosDevice: [CupertinoIcons.tv, CupertinoIcons.link, CupertinoIcons.pencil],
    emulator: [CupertinoIcons.pencil],
  };

  for (final brightness in Brightness.values) {
    testWidgets('设备操作按钮的水波纹为圆角矩形，编辑回调正常：$brightness', (tester) async {
      await withDeviceMenu(
        tester,
        (fixture) async {
          for (final entry in expectedIcons.entries) {
            final buttons = _rowButtons(entry.key);
            expect(buttons, findsNWidgets(entry.value.length));
            for (final icon in entry.value) {
              final button = find.descendant(
                of: buttons,
                matching: find.byIcon(icon),
              );
              expect(button, findsOneWidget);
            }
            for (final element in buttons.evaluate()) {
              final ink = tester.widget<InkResponse>(
                find.descendant(
                  of: find.byWidget(element.widget),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is InkResponse,
                  ),
                ),
              );
              expect(
                ink.customBorder,
                const RoundedRectangleBorder(
                  borderRadius: AppThemeSizes.radiusSmall,
                ),
              );
              expect(ink.containedInkWell, isTrue);
              expect(ink.splashFactory, isNot(NoSplash.splashFactory));
            }
          }

          // 离线共享仍禁用；编辑入口仍可点击，并且不会触发设备行跳转。
          final offlineShare = tester.widget<IconButton>(
            _rowButtons(deviceMenuOffline).at(0),
          );
          expect(offlineShare.onPressed, isNull);
          await tester.tap(_rowButtons(emulator));
          // 设备行同时支持双击，等待其手势仲裁窗口结束。
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pumpAndSettle();
          expect(find.byType(DeviceInfoEditDialog), findsOneWidget);
          expect(
            fixture.router.routeInformationProvider.value.uri.path,
            '/devices',
          );
          expect(tester.takeException(), isNull);
        },
        devices: expectedIcons.keys.toList(),
        brightness: brightness,
        language: brightness == Brightness.dark ? 'en' : 'zh',
      );
    });
  }
}
