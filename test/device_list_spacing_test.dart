import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/features/devices/widgets/device_status_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/device_context_menu_fixture.dart';

/// 在真实设备管理页对照普通列表与批量模式的几何位置。
void main() {
  for (final language in ['zh', 'en']) {
    testWidgets('普通列表与批量模式共用对齐线 $language', (tester) async {
      await withDeviceMenu(
        tester,
        (_) async {
          Finder byKey(String id) => find.byKey(ValueKey(id));
          await tester.tap(byKey('deviceView-list'));
          await tester.pumpAndSettle();
          if (language == 'en') {
            tester.platformDispatcher.textScaleFactorTestValue = 1.2;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await tester.pumpAndSettle();
          }
          final header = byKey('deviceTableHeader');
          final toolbar = byKey('deviceBatchActions');
          final row = byKey('device-row-device-a');
          final status = byKey('device-status-column-device-a');
          final version = byKey('device-system-column-device-a');
          final search = byKey('deviceListSearch');
          final manage = byKey('deviceBatchManage');
          final avatar = find.descendant(
            of: row,
            matching: find.byType(DeviceStatusAvatar),
          );
          final more = find.descendant(
            of: row,
            matching: find.widgetWithIcon(IconButton, Icons.more_horiz),
          );
          final l10n = AppLocalizations(Locale(language));
          final nameTitle = find.text(l10n.t('deviceNameCol'));
          final statusTitle = find.text(
            l10n.t('deviceWorkspaceConnectionStatus'),
          );
          final headerRect = tester.getRect(header);
          final rowRect = tester.getRect(row);
          final searchRect = tester.getRect(search);
          final statusRect = tester.getRect(status);
          final versionRect = tester.getRect(version);
          final contentLeft = tester.getRect(byKey('deviceFilter-all')).left;
          final contentRight = tester.getRect(manage).right;

          // 普通表头、筛选栏和行内容共用两侧留白。
          expect(tester.getTopLeft(nameTitle).dx, closeTo(contentLeft, .1));
          expect(tester.getTopLeft(avatar).dx, closeTo(contentLeft, .1));
          expect(tester.getRect(more).right, closeTo(contentRight, .1));
          expect(
            tester.getTopLeft(statusTitle).dx,
            closeTo(statusRect.left, .1),
          );
          expect(
            contentLeft - rowRect.left,
            closeTo(rowRect.right - contentRight, .1),
          );
          expect(tester.getCenter(avatar).dy, closeTo(rowRect.center.dy, .1));

          await tester.tap(manage);
          await tester.pumpAndSettle();
          expect(header, findsNothing);
          expect(tester.getRect(toolbar), headerRect);
          expect(tester.getRect(row), rowRect);
          expect(tester.getRect(search), searchRect);
          expect(tester.getRect(status), statusRect);
          expect(tester.getRect(version), versionRect);
          expect(more, findsNothing);
          final selectAll = byKey('deviceSelectAll');
          final rowCheck = find.descendant(
            of: row,
            matching: find.byType(Checkbox),
          );
          expect(
            tester.getCenter(selectAll).dx,
            closeTo(tester.getCenter(rowCheck).dx, .1),
          );
          expect(tester.getCenter(rowCheck).dy, closeTo(rowRect.center.dy, .1));

          await tester.tap(manage);
          await tester.pumpAndSettle();
          expect(toolbar, findsNothing);
          expect(tester.getRect(header), headerRect);
          expect(tester.getRect(row), rowRect);
          expect(tester.getRect(search), searchRect);
          expect(find.byType(Checkbox), findsNothing);
          expect(tester.takeException(), isNull);
        },
        devices: const [deviceMenuAndroid, deviceMenuTarget],
        language: language,
      );
    });
  }
}
