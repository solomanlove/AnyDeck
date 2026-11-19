import 'dart:ui' as ui;

import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/app/window/widget/desktop_workspace_surface.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:any_deck/features/devices/widgets/host_network_footer.dart';
import 'package:any_deck/features/widgets/dashboard_header_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证真实主窗口左右分区、分隔线及标题栏与底栏的最终背景绘制。
Future<void> expectDashboardSurfaceSeparation(WidgetTester tester) async {
  final rail = find.byType(PrimaryRail);
  final divider = find.byKey(const Key('dashboardNavigationDivider'));
  final workspace = find.byKey(const Key('dashboardWorkspaceSurface'));
  final railRect = tester.getRect(rail);
  final dividerRect = tester.getRect(divider);
  final workspaceRect = tester.getRect(workspace);
  final headerRect = tester.getRect(find.byType(DashboardHeaderBar));
  final footerRect = tester.getRect(find.byType(HostNetworkFooter));
  expect(
    find.descendant(
      of: find.byType(HostNetworkFooter),
      matching: find.byType(DesktopWorkspaceSurface),
    ),
    findsOneWidget,
  );
  expect(dividerRect.width, AppThemeSizes.borderWidth);
  expect(dividerRect.left, railRect.right);
  expect(dividerRect.right, workspaceRect.left);
  expect(dividerRect.top, workspaceRect.top);
  expect(dividerRect.bottom, workspaceRect.bottom);
  expect(
    find.descendant(of: rail, matching: find.byType(BackdropFilter)),
    findsNothing,
  );

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.ancestor(of: rail, matching: find.byType(RepaintBoundary)).first,
  );
  final sampleY = railRect.center.dy;
  final points = [
    Offset(railRect.right - 2, sampleY),
    Offset(dividerRect.center.dx, sampleY),
    Offset(workspaceRect.left + 2, sampleY),
    Offset(workspaceRect.center.dx, headerRect.top + 4),
    Offset(workspaceRect.center.dx, footerRect.center.dy),
  ];
  // 采样两侧留白和分隔线的最终像素，避免仅比较配置却未实际绘制。
  final colors = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return points.map((point) {
        final local = boundary.globalToLocal(point);
        final offset = (local.dy.floor() * image.width + local.dx.floor()) * 4;
        return Color.fromARGB(
          bytes.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
      }).toList();
    } finally {
      image.dispose();
    }
  });
  final theme = Theme.of(tester.element(rail));
  expect(colors![0], theme.navigationSurface);
  expect(colors[1], tester.widget<VerticalDivider>(divider).color);
  expect(
    (colors[0].computeLuminance() - colors[2].computeLuminance()).abs(),
    greaterThan(0.008),
    reason: '左右背景必须有可见的明暗层次',
  );
  // 毛玻璃上下相邻内容不同，允许不超过两个色阶的模糊合成差异。
  for (final channel in [
    (colors[4].r, colors[3].r),
    (colors[4].g, colors[3].g),
    (colors[4].b, colors[3].b),
  ]) {
    expect(
      channel.$1,
      closeTo(channel.$2, 2 / 255 + 0.000001),
      reason: '全局底栏与当前页面标题栏背景必须一致',
    );
  }
}
