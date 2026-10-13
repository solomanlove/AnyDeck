import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    // 验证图标与操作按钮
    expect(find.byIcon(Icons.devices_rounded), findsOneWidget);
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
            icon: CupertinoIcons.sparkles,
            trailing: Text('运行中 (端口: 8080)'),
          ),
        ),
      ),
    );

    expect(find.text('AI MCP'), findsOneWidget);
    expect(find.text('AI MCP 服务与工具集'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.sparkles), findsOneWidget);
    expect(find.text('运行中 (端口: 8080)'), findsOneWidget);
  });
}
