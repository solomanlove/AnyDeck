import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:any_deck/features/devices/model/device_context_action.dart';
import 'package:any_deck/features/devices/widgets/device_info_edit_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 工作区列表使用一个主操作和更多菜单，按稳定设备 key 验证真实入口。
Finder _row(RegisteredDevice device) =>
    find.byKey(ValueKey('device-row-${device.id}'));

Future<void> _showList(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('deviceView-list')));
  await tester.pumpAndSettle();
}

void main() {
  final networkDevice = deviceMenuTarget.copyWith(
    connections: ['192.0.2.20:5555'],
  );
  final harmonyDevice = deviceMenuHarmony.copyWith(
    connections: ['192.0.2.21:5555'],
  );
  final iosDevice = deviceMenuIos.copyWith(ipAddress: '192.0.2.22');
  const emulator = RegisteredDevice(
    id: 'emulator-5554',
    model: '离线模拟器',
    status: 'offline',
    isOnline: false,
  );
  final devices = [
    deviceMenuAndroid,
    networkDevice,
    deviceMenuOffline,
    harmonyDevice,
    iosDevice,
    emulator,
  ];

  for (final brightness in Brightness.values) {
    for (final themeColor in AppThemeColor.values) {
      testWidgets('设备主操作跟随主题，编辑与平台菜单能力保留：$brightness / $themeColor', (
        tester,
      ) async {
        await withDeviceMenu(
          tester,
          (fixture) async {
            await _showList(tester);
            for (final device in devices) {
              final primary = find.descendant(
                of: _row(device),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is FilledButton || widget is OutlinedButton,
                ),
              );
              expect(primary, findsOneWidget);
              final button = tester.widget<ButtonStyleButton>(primary);
              final theme = Theme.of(tester.element(primary));
              final scheme = theme.colorScheme;
              expect(scheme.primary, themeColor.color);
              expect(
                button.style!.foregroundColor!.resolve({}),
                device.isOnline ? scheme.primary : scheme.onSurfaceVariant,
              );
              expect(button.onPressed, isNotNull);

              await fixture.openMenu(tester, device);
              final edit = deviceMenuAction(DeviceContextAction.edit);
              expect(edit, findsOneWidget);
              // 从已展开的菜单项定位面板，校验根层 Overlay 沿用设备工作区底色。
              final panel = tester.widget<Material>(
                find.ancestor(of: edit, matching: find.byType(Material)).first,
              );
              expect(panel.color, theme.appColors.panelSurface);
              expect(panel.surfaceTintColor, Colors.transparent);
              expect(
                tester.widget<PopupMenuItem<DeviceContextAction>>(edit).enabled,
                isTrue,
              );
              expect(
                find.descendant(
                  of: edit,
                  matching: find.byIcon(CupertinoIcons.pencil),
                ),
                findsOneWidget,
              );
              final localAndroid =
                  !device.isIos &&
                  !device.isHarmony &&
                  !device.id.startsWith('emulator-');
              expect(
                deviceMenuAction(DeviceContextAction.share),
                localAndroid ? findsOneWidget : findsNothing,
              );
              expect(
                deviceMenuAction(DeviceContextAction.wireless),
                localAndroid ? findsOneWidget : findsNothing,
              );
              if (localAndroid) {
                expect(
                  tester
                      .widget<PopupMenuItem<DeviceContextAction>>(
                        deviceMenuAction(DeviceContextAction.share),
                      )
                      .enabled,
                  device.isOnline,
                );
              }
              await fixture.closeMenu(tester);
            }
            expect(tester.takeException(), isNull);
          },
          devices: devices,
          brightness: brightness,
          themeColor: themeColor,
        );
      });
    }

    testWidgets('设备主操作保持圆角与内边距，菜单编辑不会触发设备导航：$brightness', (tester) async {
      await withDeviceMenu(
        tester,
        (fixture) async {
          await _showList(tester);
          for (final device in devices) {
            final primary = find.descendant(
              of: _row(device),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton || widget is OutlinedButton,
              ),
            );
            final button = tester.widget<ButtonStyleButton>(primary);
            expect(
              button.style!.shape!.resolve({}),
              const RoundedRectangleBorder(
                borderRadius: AppThemeSizes.radiusMedium,
              ),
            );
            expect(
              button.style!.padding!.resolve({}),
              const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            );
            expect(tester.getSize(primary).height, greaterThanOrEqualTo(31));
          }
          await fixture.openMenu(tester, deviceMenuOffline);
          expect(
            tester
                .widget<PopupMenuItem<DeviceContextAction>>(
                  deviceMenuAction(DeviceContextAction.share),
                )
                .enabled,
            isFalse,
          );
          await fixture.closeMenu(tester);
          await fixture.openMenu(tester, emulator);
          await tester.tap(deviceMenuAction(DeviceContextAction.edit));
          await tester.pumpAndSettle();
          expect(find.byType(DeviceInfoEditDialog), findsOneWidget);
          expect(
            fixture.router.routeInformationProvider.value.uri.path,
            '/devices',
          );
          expect(tester.takeException(), isNull);
        },
        devices: devices,
        brightness: brightness,
        language: brightness == Brightness.dark ? 'en' : 'zh',
      );
    });
  }
}
