import 'package:any_deck/core/providers/modules/registered_device_model.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 使用真实列表验证表头排序、状态优先级与视图切换，不启动设备命令。
const _devices = [
  RegisteredDevice(
    id: 'ten',
    model: 'Ten',
    status: 'device',
    isOnline: true,
    androidVersion: 'Android 10 (API 29)',
  ),
  RegisteredDevice(
    id: 'nine',
    model: 'Nine',
    status: 'device',
    isOnline: true,
    androidVersion: 'Android 9 (API 28)',
  ),
  RegisteredDevice(
    id: 'seventeen',
    model: 'Seventeen',
    status: 'device',
    isOnline: true,
    androidVersion: 'Android 17 (API 37)',
  ),
  RegisteredDevice(
    id: 'unknown',
    model: 'Unknown',
    status: 'device',
    isOnline: true,
  ),
  RegisteredDevice(
    id: 'offline-new',
    model: 'Offline new',
    status: 'offline',
    isOnline: false,
    androidVersion: 'Android 17 (API 37)',
  ),
  RegisteredDevice(
    id: 'offline-old',
    model: 'Offline old',
    status: 'offline',
    isOnline: false,
    androidVersion: 'Android 9 (API 28)',
  ),
];

List<String> _rowOrder(WidgetTester tester) => tester
    .widgetList<InkWell>(
      find.byWidgetPredicate(
        (widget) =>
            widget is InkWell &&
            widget.key is ValueKey<String> &&
            (widget.key as ValueKey<String>).value.startsWith('device-row-'),
      ),
    )
    .map(
      (widget) => (widget.key as ValueKey<String>).value.substring(
        'device-row-'.length,
      ),
    )
    .toList();

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('系统版本表头 $language ${brightness.name} 数字升降序并保留在线优先', (
        tester,
      ) async {
        await withDeviceMenu(
          tester,
          (fixture) async {
            await tester.tap(find.byKey(const Key('deviceView-list')));
            await tester.pumpAndSettle();
            final header = find.byKey(const Key('deviceSystemVersionSort'));
            expect(
              find.descendant(
                of: header,
                matching: find.byIcon(CupertinoIcons.chevron_up_chevron_down),
              ),
              findsOneWidget,
            );
            await tester.tap(header);
            await tester.pumpAndSettle();
            expect(_rowOrder(tester), [
              'nine',
              'ten',
              'seventeen',
              'unknown',
              'offline-old',
              'offline-new',
            ]);
            expect(
              find.descendant(
                of: header,
                matching: find.byIcon(CupertinoIcons.chevron_up),
              ),
              findsOneWidget,
            );
            await tester.tap(header);
            await tester.pumpAndSettle();
            const descending = [
              'seventeen',
              'ten',
              'nine',
              'unknown',
              'offline-new',
              'offline-old',
            ];
            expect(_rowOrder(tester), descending);
            expect(
              find.descendant(
                of: header,
                matching: find.byIcon(CupertinoIcons.chevron_down),
              ),
              findsOneWidget,
            );
            await tester.tap(find.byKey(const Key('deviceView-wall')));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widgetList<DeviceWallCard>(find.byType(DeviceWallCard))
                  .map((card) => (card.key as ValueKey<String>).value),
              descending.map((id) => 'device-wall-$id'),
            );
            await tester.tap(find.byKey(const Key('deviceView-list')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('deviceFilter-offline')));
            await tester.pumpAndSettle();
            expect(_rowOrder(tester), ['offline-new', 'offline-old']);
            expect(fixture.adb.captures, isEmpty);
            expect(tester.takeException(), isNull);
          },
          devices: _devices,
          language: language,
          brightness: brightness,
        );
      });
    }
  }
}
