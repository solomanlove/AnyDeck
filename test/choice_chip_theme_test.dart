import 'package:any_deck/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _chip(String scope, String name) => find.byKey(ValueKey('$scope-$name'));

/// 当前 SDK 通过 Ink 绘制背景；兼容直接在 Material 设置颜色的实现。
Color? _background(WidgetTester tester, Finder finder) {
  final material = tester.widget<Material>(
    find.descendant(of: finder, matching: find.byType(Material)).first,
  );
  if (material.color != null) return material.color;
  final ink = tester.widget<Ink>(
    find.descendant(of: finder, matching: find.byType(Ink)).first,
  );
  return (ink.decoration! as ShapeDecoration).color;
}

/// 从已挂载控件读取最终文字样式，包含 RawChip 的合并与状态解析。
TextStyle _textStyle(WidgetTester tester, Finder finder) => DefaultTextStyle.of(
  tester.element(find.descendant(of: finder, matching: find.byType(Text))),
).style;

/// 比较实际背景、文字及 Material 形状，避免未选中和普通 Chip 受全局配置影响。
Object _style(WidgetTester tester, Finder finder) {
  final material = tester.widget<Material>(
    find.descendant(of: finder, matching: find.byType(Material)).first,
  );
  return (
    _background(tester, finder),
    _textStyle(tester, finder),
    material.shape,
    material.elevation,
  );
}

/// Material 先绘制填充路径，勾选是后续的描边路径。
PaintPattern _paintsCheckmark(Color color) => paints
  ..something(
    (method, arguments) =>
        method == #drawPath &&
        (arguments[1] as Paint).style == PaintingStyle.stroke &&
        (arguments[1] as Paint).color.toARGB32() == color.toARGB32(),
  );

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('默认 ChoiceChip 六种主题色的实际选中样式与覆盖边界 $brightness', (tester) async {
      for (final color in AppThemeColor.values) {
        var callbacks = 0;
        Widget chips(String scope) => Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: ValueKey('$scope-selected'),
              label: const Text('选中'),
              selected: true,
              onSelected: (_) => callbacks++,
            ),
            ChoiceChip(
              key: ValueKey('$scope-unselected'),
              label: const Text('未选中'),
              selected: false,
              onSelected: (_) => callbacks++,
            ),
            ChoiceChip(
              key: ValueKey('$scope-disabled'),
              label: const Text('禁用'),
              selected: true,
              onSelected: null,
            ),
            ChoiceChip(
              key: ValueKey('$scope-custom'),
              label: const Text('自定义'),
              selected: true,
              selectedColor: Colors.amber,
              labelStyle: const TextStyle(color: Colors.black),
              checkmarkColor: Colors.deepPurple,
              onSelected: (_) => callbacks++,
            ),
            Chip(key: ValueKey('$scope-plain'), label: const Text('普通')),
          ],
        );
        final theme = buildAppTheme(brightness, themeColor: color);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  chips('theme'),
                  Theme(
                    data: theme.copyWith(chipTheme: const ChipThemeData()),
                    child: chips('baseline'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selected = _chip('theme', 'selected');
        expect(
          _background(tester, selected),
          theme.colorScheme.primaryContainer,
        );
        expect(
          _textStyle(tester, selected).color,
          theme.colorScheme.onPrimaryContainer,
        );
        expect(
          selected,
          _paintsCheckmark(theme.colorScheme.onPrimaryContainer),
        );
        for (final name in ['unselected', 'plain']) {
          expect(
            _style(tester, _chip('theme', name)),
            _style(tester, _chip('baseline', name)),
          );
        }
        final custom = _chip('theme', 'custom');
        expect(_background(tester, custom), Colors.amber);
        expect(_textStyle(tester, custom).color, Colors.black);
        expect(custom, _paintsCheckmark(Colors.deepPurple));
        await tester.tap(_chip('theme', 'disabled'));
        await tester.pumpAndSettle();
        expect(callbacks, 0);
        expect(
          tester.widget<ChoiceChip>(_chip('theme', 'disabled')).selected,
          isTrue,
        );
        await tester.tap(_chip('theme', 'unselected'));
        await tester.pumpAndSettle();
        expect(callbacks, 1);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
