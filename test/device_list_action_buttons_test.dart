import 'package:any_deck/app/theme/app_theme.dart';
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
    for (final themeColor in AppThemeColor.values) {
      testWidgets('设备编辑图标与投屏、连接图标同色：$brightness / $themeColor', (tester) async {
        await withDeviceMenu(
          tester,
          (fixture) async {
            // 三平台及离线设备共用主题主色，避免编辑图标保留固定蓝色。
            for (final device in expectedIcons.keys) {
              final buttons = _rowButtons(device);
              final edit = find.descendant(
                of: buttons,
                matching: find.byIcon(CupertinoIcons.pencil),
              );
              final primary = Theme.of(
                tester.element(edit),
              ).colorScheme.primary;
              final editColor = tester.widget<Icon>(edit).color;
              expect(editColor, primary);
              expect(primary, themeColor.color);
              for (final icon in [CupertinoIcons.tv, CupertinoIcons.link]) {
                final adjacent = find.descendant(
                  of: buttons,
                  matching: find.byIcon(icon),
                );
                if (adjacent.evaluate().isNotEmpty) {
                  expect(tester.widget<Icon>(adjacent).color, editColor);
                }
              }
            }
            expect(tester.takeException(), isNull);
          },
          devices: expectedIcons.keys.toList(),
          brightness: brightness,
          themeColor: themeColor,
        );
      });
    }

    testWidgets('设备操作按钮的圆角水波纹保留内边距，编辑回调正常：$brightness', (tester) async {
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
              final button = find.byWidget(element.widget);
              final inkFinder = find.descendant(
                of: button,
                matching: find.byWidgetPredicate(
                  (widget) => widget is InkResponse,
                ),
              );
              final ink = tester.widget<InkResponse>(inkFinder);
              expect(
                ink.customBorder,
                const RoundedRectangleBorder(
                  borderRadius: AppThemeSizes.radiusSmall,
                ),
              );
              expect(ink.containedInkWell, isTrue);
              expect(ink.splashFactory, isNot(NoSplash.splashFactory));
              // 检查真实水波纹边界，避免只扩大外围点击区域而没有图标留白。
              final inkRect = tester.getRect(inkFinder);
              final iconRect = tester.getRect(
                find.descendant(of: button, matching: find.byType(Icon)),
              );
              for (final padding in [
                iconRect.left - inkRect.left,
                inkRect.right - iconRect.right,
                iconRect.top - inkRect.top,
                inkRect.bottom - iconRect.bottom,
              ]) {
                expect(padding, greaterThanOrEqualTo(8));
              }
            }
          }

          // 离线共享仍禁用；编辑入口仍可点击，并且不会触发设备行跳转。
          final offlineShare = tester.widget<IconButton>(
            _rowButtons(deviceMenuOffline).at(0),
          );
          expect(offlineShare.onPressed, isNull);
          // 点击图标左侧新增的内边距，仍应触发编辑操作。
          final editInk = tester.getRect(
            find.descendant(
              of: _rowButtons(emulator),
              matching: find.byWidgetPredicate(
                (widget) => widget is InkResponse,
              ),
            ),
          );
          await tester.tapAt(Offset(editInk.left + 4, editInk.center.dy));
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
