import 'package:any_deck/app/theme/app_icon.dart';
import 'package:any_deck/features/overview/widget/service_restart_menu_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/shortcut_test_fixture.dart';

/// 打开真实服务菜单，验证品牌资源加载、菜单完整性及图标列对齐，不执行重启操作。
void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness 服务菜单加载公共平台 Logo 并保持文本对齐', (tester) async {
      final state = ProviderContainer();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        shortcutTestApp(
          container: state,
          brightness: brightness,
          child: const ServiceRestartMenuButton(iconColor: Colors.grey),
        ),
      );
      await tester.tap(find.byType(ServiceRestartMenuButton));
      await tester.pumpAndSettle();
      final items = find.byType(PopupMenuItem<String>);
      expect(items, findsNWidgets(5));
      final rows = [
        for (final value in ['restart_adb', 'restart_hdc', 'restart_ios'])
          find.byWidgetPredicate(
            (widget) =>
                widget is PopupMenuItem<String> && widget.value == value,
          ),
      ];
      final huawei = find.descendant(of: rows[1], matching: find.byType(Image));
      expect(
        tester.widget<Image>(huawei).image,
        const AssetImage(AppIcons.huaweiPetal),
      );
      expect(
        find.descendant(
          of: rows[0],
          matching: find.byIcon(Icons.android_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rows[2], matching: find.byIcon(Icons.apple)),
        findsOneWidget,
      );
      final textLeft = rows
          .map(
            (row) => tester
                .getTopLeft(
                  find.descendant(of: row, matching: find.byType(Text)),
                )
                .dx,
          )
          .toList();
      expect(textLeft[0], textLeft[1]);
      expect(textLeft[1], textLeft[2]);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
