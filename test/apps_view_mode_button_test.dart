import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/apps/widgets/apps_view_mode_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('应用视图按钮仅在 selected 状态显示品牌绿色 Icon', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Row(
            children: [
              AppsViewModeButton(
                key: const Key('selectedView'),
                tooltip: '网格模式',
                icon: Icons.grid_view_outlined,
                selectedIcon: Icons.grid_view_rounded,
                selected: true,
                onPressed: () => pressed = true,
              ),
              AppsViewModeButton(
                key: const Key('unselectedView'),
                tooltip: '列表模式',
                icon: Icons.list,
                selected: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final selected = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('selectedView')),
        matching: find.byType(IconButton),
      ),
    );
    final unselected = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('unselectedView')),
        matching: find.byType(IconButton),
      ),
    );

    expect((selected.selectedIcon! as Icon).color, AppPalette.primary);
    expect((unselected.icon as Icon).color, isNull);

    await tester.tap(find.byKey(const Key('selectedView')));
    expect(pressed, isTrue);
  });
}
