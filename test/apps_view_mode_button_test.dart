import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/apps/widgets/apps_view_mode_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('应用视图按钮 selected 状态保持线框 Icon 并显示绿色背景', (tester) async {
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

    final selectedIcon = selected.selectedIcon! as Icon;
    expect(selectedIcon.icon, Icons.grid_view_outlined);
    expect(selectedIcon.color, AppPalette.primary);
    expect(
      selected.style!.backgroundColor!.resolve(<WidgetState>{}),
      AppPalette.primary.withValues(alpha: 0.12),
    );
    expect((unselected.icon as Icon).color, isNull);
    expect(
      unselected.style!.backgroundColor!.resolve(<WidgetState>{}),
      Colors.transparent,
    );

    await tester.tap(find.byKey(const Key('selectedView')));
    expect(pressed, isTrue);
  });
}
