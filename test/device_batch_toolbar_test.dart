import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/core/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 通过真实设备管理页面验证批量工具栏的排序、选择、能力与表头替换。
const _actions = [
  'mirror',
  'screenshot',
  'record',
  'install',
  'push',
  'script',
  'schedule',
  'delete',
];

Finder _action(String action) => find.byKey(Key('deviceBatch-$action'));

Future<void> _enterBatch(WidgetTester tester, {bool list = false}) async {
  if (list) {
    await tester.tap(find.byKey(const Key('deviceView-list')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('deviceBatchManage')));
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      for (final width in [1200.0, 490.0, 320.0]) {
        testWidgets('批量按钮保序且单行滚动无溢出 $language $brightness ${width.toInt()}px', (
          tester,
        ) async {
          if (width == 320) {
            tester.platformDispatcher.textScaleFactorTestValue = 1.6;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
          }
          await withDeviceMenu(
            tester,
            (fixture) async {
              await _enterBatch(tester, list: true);
              final toolbar = find.byKey(const Key('deviceBatchActions'));
              expect(tester.widget<Container>(toolbar), isNotNull);
              expect(
                find.descendant(
                  of: toolbar,
                  matching: find.byType(PopupMenuButton<String>),
                ),
                findsNothing,
              );
              final l10n = AppLocalizations(Locale(language));
              final expected = [
                l10n.t('deviceWorkspaceSelectAll').replaceAll('{count}', '0'),
                l10n.t('batchMirror'),
                l10n.t('deviceWorkspaceBatchScreenshot'),
                l10n.t('screenRecord'),
                l10n.t('deviceWorkspaceBatchInstall'),
                l10n.t('batchPush'),
                l10n.t('batchScript'),
                l10n.t('deviceWorkspaceBatchSchedule'),
                l10n.t('deviceWorkspaceBatchDelete'),
              ];
              expect(
                tester
                    .widgetList<Text>(
                      find.descendant(of: toolbar, matching: find.byType(Text)),
                    )
                    .map((text) => text.data),
                expected,
              );
              final selectAll = tester.getRect(
                find.byKey(const Key('deviceSelectAll')),
              );
              var right = selectAll.right;
              for (final action in _actions) {
                final bounds = tester.getRect(_action(action));
                expect(bounds.left, greaterThanOrEqualTo(right));
                expect(bounds.center.dy, closeTo(selectAll.center.dy, .1));
                right = bounds.right;
              }
              expect(find.byKey(const Key('deviceTableHeader')), findsNothing);
              final horizontal = find.descendant(
                of: toolbar,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is SingleChildScrollView &&
                      widget.scrollDirection == Axis.horizontal,
                ),
              );
              expect(horizontal, findsOneWidget);
              await tester.drag(horizontal, const Offset(-5000, 0));
              await tester.pumpAndSettle();
              final last = tester.getRect(_action('delete'));
              final bar = tester.getRect(toolbar);
              expect(last.right, greaterThan(bar.left));
              expect(last.right, lessThanOrEqualTo(bar.right));
              if (last.width <= bar.width - 16) {
                expect(last.left, greaterThanOrEqualTo(bar.left));
              }
              expect(tester.takeException(), isNull);
            },
            devices: const [deviceMenuAndroid, deviceMenuTarget],
            language: language,
            brightness: brightness,
            windowSize: Size(width, 1100),
          );
        });
      }
    }
  }

  testWidgets('管理模式在原表头位置显示操作栏，退出恢复表头与设备行位置', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await tester.tap(find.byKey(const Key('deviceView-list')));
      await tester.pumpAndSettle();
      final header = find.byKey(const Key('deviceTableHeader'));
      final top = tester.getTopLeft(header).dy;
      final row = find.byKey(const ValueKey('device-row-device-a'));
      final rowTop = tester.getTopLeft(row).dy;
      await _enterBatch(tester);
      expect(header, findsNothing);
      final toolbar = find.byKey(const Key('deviceBatchActions'));
      expect(toolbar, findsOneWidget);
      expect(tester.getTopLeft(toolbar).dy, closeTo(top, .1));
      expect(tester.getTopLeft(row).dy, closeTo(rowTop, .1));
      expect(find.text('设备名称'), findsNothing);
      expect(find.text('连接状态'), findsNothing);
      await tester.tap(find.byKey(const Key('deviceBatchManage')));
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing);
      expect(header, findsOneWidget);
      expect(tester.getTopLeft(header).dy, closeTo(top, .1));
      expect(tester.getTopLeft(row).dy, closeTo(rowTop, .1));
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
    }, devices: const [deviceMenuAndroid, deviceMenuTarget]);
  });

  testWidgets('全选计数、三态与筛选隐藏选择联动，退出清空勾选', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _enterBatch(tester, list: true);
      final all = find.byKey(const Key('deviceSelectAll'));
      expect(find.text('全选(0)'), findsOneWidget);
      expect(tester.widget<Checkbox>(all).value, isFalse);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('全选(2)'), findsOneWidget);
      expect(tester.widget<Checkbox>(all).value, isTrue);
      expect(
        fixture.container
            .read(deviceRegistryProvider)
            .every((d) => d.isChecked),
        isTrue,
      );
      final alpha = find.byKey(const ValueKey('device-row-device-a'));
      await tester.tap(
        find.descendant(of: alpha, matching: find.byType(Checkbox)),
      );
      await tester.pumpAndSettle();
      expect(find.text('全选(1)'), findsOneWidget);
      expect(tester.widget<Checkbox>(all).value, isNull);
      await tester.enterText(find.byKey(const Key('deviceListSearch')), '设备甲');
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(all).value, isFalse);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('全选(2)'), findsOneWidget);
      expect(tester.widget<Checkbox>(all).value, isTrue);
      await tester.tap(all);
      await tester.pumpAndSettle();
      expect(find.text('全选(1)'), findsOneWidget);
      expect(
        fixture.container
            .read(deviceRegistryProvider)
            .singleWhere((d) => d.id == deviceMenuTarget.id)
            .isChecked,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('deviceBatchManage')));
      await tester.pumpAndSettle();
      expect(
        fixture.container
            .read(deviceRegistryProvider)
            .every((d) => !d.isChecked),
        isTrue,
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(tester.takeException(), isNull);
    }, devices: const [deviceMenuAndroid, deviceMenuTarget]);
  });

  for (final entry in [
    ('未选择', deviceMenuAndroid, false, <String>{}),
    ('Android', deviceMenuAndroid, true, _actions.toSet()),
    ('HarmonyOS', deviceMenuHarmony, true, {'mirror', 'script', 'delete'}),
    ('iOS', deviceMenuIos, true, {'mirror', 'delete'}),
    ('离线', deviceMenuOffline, true, {'delete'}),
  ]) {
    testWidgets('${entry.$1} 批量操作按平台与在线状态禁用', (tester) async {
      await withDeviceMenu(tester, (fixture) async {
        await _enterBatch(tester);
        for (final action in _actions) {
          expect(
            tester.widget<TextButton>(_action(action)).onPressed != null,
            entry.$4.contains(action),
            reason: '${entry.$1}: $action',
          );
        }
        expect(tester.takeException(), isNull);
      }, devices: [entry.$2.copyWith(isChecked: entry.$3)]);
    });
  }

  testWidgets('筛选无结果仍保留隐藏选择与删除入口', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _enterBatch(tester, list: true);
      await tester.enterText(
        find.byKey(const Key('deviceListSearch')),
        'not-present',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('deviceBatchActions')), findsOneWidget);
      expect(find.text('全选(1)'), findsOneWidget);
      expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('deviceSelectAll')))
            .onChanged,
        isNull,
      );
      expect(tester.widget<TextButton>(_action('delete')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    }, devices: [deviceMenuOffline.copyWith(isChecked: true)]);
  });

  testWidgets('脚本配置等待期间禁用批量动作，取消后恢复', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _enterBatch(tester);
      final script = _action('script');
      await tester.ensureVisible(script);
      await tester.tap(script);
      await tester.pumpAndSettle();
      for (final action in _actions) {
        expect(tester.widget<TextButton>(_action(action)).onPressed, isNull);
      }
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<TextButton>(script).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    }, devices: [deviceMenuAndroid.copyWith(isChecked: true)]);
  });

  testWidgets('定时任务从工具栏直接打开对话框', (tester) async {
    await withDeviceMenu(tester, (fixture) async {
      await _enterBatch(tester);
      final schedule = _action('schedule');
      await tester.ensureVisible(schedule);
      await tester.tap(schedule);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('创建新任务'), findsOneWidget);
      expect(find.text('任务管理列表'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, devices: [deviceMenuAndroid.copyWith(isChecked: true)]);
  });
}
