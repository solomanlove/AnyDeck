import 'package:any_deck/core/device_groups/device_groups_controller.dart';
import 'package:any_deck/features/devices/widgets/device_wall_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 通过真实 Dashboard 验证分组、搜索、状态及视图共享同一过滤链路。
Future<void> _chooseGroup(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('deviceGroupFilter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('deviceGroupOption-$id')));
  await tester.pumpAndSettle();
}

Future<void> _manageGroups(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('deviceGroupFilter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('deviceGroupManage')));
  await tester.pumpAndSettle();
}

Future<void> _saveName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('deviceGroupNameInput')), name);
  await tester.tap(find.byKey(const Key('deviceGroupNameSave')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('自定义归属随注册表补齐serial并切换无线通道继续保留', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      final controller = fixture.container.read(deviceGroupsProvider.notifier);
      final groupId = await controller.createGroup('日常设备');
      await controller.setMembership(groupId, deviceMenuAndroid, true);
      await tester.pumpAndSettle();
      await _chooseGroup(tester, groupId);
      expect(find.byType(DeviceWallCard), findsOneWidget);
      final physical = deviceMenuAndroid.copyWith(serial: 'physical-android');
      fixture.registry.state = [physical];
      await tester.pumpAndSettle();
      expect(
        fixture.container
            .read(deviceGroupsProvider)
            .requireValue
            .customGroups
            .single
            .members
            .single
            .serial,
        'physical-android',
      );
      // 模拟设备仅保留新无线通道；同一 physical serial 仍属于原分组。
      fixture.registry.state = [physical.copyWith(id: '192.168.5.8:5555')];
      await tester.pumpAndSettle();
      expect(find.byType(DeviceWallCard), findsOneWidget);
      expect(
        find.byKey(const ValueKey('device-wall-192.168.5.8:5555')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('默认平台分组叠加在线状态和搜索，墙与列表共享结果，空态可清除', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      expect(find.byType(DeviceWallCard), findsNWidgets(5));
      await _chooseGroup(tester, 'android');
      expect(find.byType(DeviceWallCard), findsNWidgets(3));
      expect(find.text(deviceMenuHarmony.displayName), findsNothing);
      await tester.tap(find.byKey(const Key('deviceFilter-offline')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceWallCard), findsOneWidget);
      expect(find.text(deviceMenuOffline.displayName), findsOneWidget);
      await tester.tap(find.byKey(const Key('deviceView-list')));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceWallCard), findsNothing);
      expect(find.text(deviceMenuOffline.displayName), findsOneWidget);
      await tester.enterText(find.byKey(const Key('deviceListSearch')), '不存在');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deviceResetFilters')), findsOneWidget);
      await tester.tap(find.byKey(const Key('deviceResetFilters')));
      await tester.pumpAndSettle();
      for (final device in fixture.registry.devices) {
        expect(find.text(device.displayName), findsOneWidget);
      }
      await _chooseGroup(tester, 'harmony');
      expect(find.text(deviceMenuHarmony.displayName), findsOneWidget);
      expect(find.text(deviceMenuIos.displayName), findsNothing);
      await _chooseGroup(tester, 'ios');
      expect(find.text(deviceMenuIos.displayName), findsOneWidget);
      expect(find.text(deviceMenuHarmony.displayName), findsNothing);
      expect(fixture.adb.captures, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets('自定义分组 $language ${brightness.name} 可创建勾选重命名和删除', (
        tester,
      ) async {
        await withDeviceMenu(
          tester,
          (fixture) async {
            await _manageGroups(tester);
            // 默认组只展示自动成员，无法改名、删除或手工改平台归属。
            expect(find.byKey(const Key('deviceGroupRename')), findsNothing);
            expect(find.byKey(const Key('deviceGroupDelete')), findsNothing);
            final automatic = tester.widget<CheckboxListTile>(
              find.byKey(ValueKey('deviceGroupMember-${deviceMenuAndroid.id}')),
            );
            expect(automatic.value, isTrue);
            expect(automatic.onChanged, isNull);
            await tester.tap(find.byKey(const Key('deviceGroupCreate')));
            await tester.pumpAndSettle();
            await _saveName(tester, '  ANDROID  ');
            expect(
              find.byKey(const Key('deviceGroupNameInput')),
              findsOneWidget,
            );
            await _saveName(tester, '回归设备');
            final state = fixture.container
                .read(deviceGroupsProvider)
                .requireValue;
            final custom = state.customGroups.single;
            final member = find.byKey(
              ValueKey('deviceGroupMember-${deviceMenuHarmony.id}'),
            );
            await tester.scrollUntilVisible(
              member,
              80,
              scrollable: find
                  .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.tap(member);
            await tester.pumpAndSettle();
            expect(tester.widget<CheckboxListTile>(member).value, isTrue);
            expect(
              fixture.container
                  .read(deviceGroupsProvider)
                  .requireValue
                  .matches(custom.id, deviceMenuHarmony),
              isTrue,
            );
            await tester.ensureVisible(
              find.byKey(const Key('deviceGroupRename')),
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('deviceGroupRename')));
            await tester.pumpAndSettle();
            await _saveName(tester, '发布设备');
            await tester.tap(find.text(language == 'zh' ? '关闭' : 'Close'));
            await tester.pumpAndSettle();
            await _chooseGroup(tester, custom.id);
            expect(find.byType(DeviceWallCard), findsOneWidget);
            expect(find.text(deviceMenuHarmony.displayName), findsOneWidget);
            expect(find.text('发布设备'), findsOneWidget);
            await _manageGroups(tester);
            await tester.tap(find.byKey(const Key('deviceGroupDelete')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('deviceGroupDeleteConfirm')));
            await tester.pumpAndSettle();
            await tester.tap(find.text(language == 'zh' ? '关闭' : 'Close'));
            await tester.pumpAndSettle();
            expect(find.byType(DeviceWallCard), findsNWidgets(5));
            expect(fixture.registry.devices, hasLength(5));
            expect(
              fixture.container
                  .read(deviceGroupsProvider)
                  .requireValue
                  .customGroups,
              isEmpty,
            );
            expect(tester.takeException(), isNull);
          },
          language: language,
          brightness: brightness,
        );
      });
    }
  }
}
