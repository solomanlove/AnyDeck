import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('标题栏共享设备按钮与相邻操作的样式及点击反馈一致：$brightness', (tester) async {
      var presses = 0;
      final color = buildAppTheme(brightness).colorScheme.onSurfaceVariant;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: Row(
              children: [
                for (final icon in [
                  Icons.devices_outlined,
                  CupertinoIcons.link,
                ])
                  DashboardHeaderActionButton(
                    icon: Icon(icon),
                    tooltip: icon.toString(),
                    color: color,
                    onPressed: () => presses++,
                  ),
              ],
            ),
          ),
        ),
      );

      for (final icon in [Icons.devices_outlined, CupertinoIcons.link]) {
        final finder = find.widgetWithIcon(IconButton, icon);
        expect(tester.getSize(finder), const Size(48, 48));
        final iconContext = tester.element(find.byIcon(icon));
        expect(IconTheme.of(iconContext).size, 30);
        expect(IconTheme.of(iconContext).color, color);
        final ink = tester.widget<InkResponse>(
          find.descendant(
            of: finder,
            matching: find.byWidgetPredicate((widget) => widget is InkResponse),
          ),
        );
        expect(
          ink.customBorder,
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        );
        expect(ink.splashFactory, isNot(NoSplash.splashFactory));
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }
      expect(presses, 2);
    });
  }

  testWidgets('DashboardHeaderBar 基础渲染与操作按钮测试', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(
          body: DashboardHeaderBar(
            title: '测试主标题',
            subtitle: '测试副标题描述',
            icon: Icons.devices_rounded,
            actions: [
              IconButton(
                onPressed: null,
                icon: Icon(CupertinoIcons.refresh),
              ),
            ],
          ),
        ),
      ),
    );

    // 验证标题与副标题
    expect(find.text('测试主标题'), findsOneWidget);
    expect(find.text('测试副标题描述'), findsOneWidget);

    // 验证图标已删除（不再渲染徽标图标），操作按钮正常保留
    expect(find.byIcon(Icons.devices_rounded), findsNothing);
    expect(find.byIcon(CupertinoIcons.refresh), findsOneWidget);
  });

  testWidgets('DashboardHeaderBar trailing 属性渲染测试', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        home: const Scaffold(
          body: DashboardHeaderBar(
            title: 'AI MCP',
            subtitle: 'AI MCP 服务与工具集',
            trailing: Text('运行中 (端口: 8080)'),
          ),
        ),
      ),
    );

    expect(find.text('AI MCP'), findsOneWidget);
    expect(find.text('AI MCP 服务与工具集'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.sparkles), findsNothing);
    expect(find.text('运行中 (端口: 8080)'), findsOneWidget);
  });
}
