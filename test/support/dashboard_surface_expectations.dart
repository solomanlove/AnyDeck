import 'dart:ui' as ui;

import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/features/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证真实主窗口的两侧绘制有明暗层次，分隔线完整且不被子页面盖住。
Future<void> expectDashboardSurfaceSeparation(WidgetTester tester) async {
  final rail = find.byType(PrimaryRail);
  final divider = find.byKey(const Key('dashboardNavigationDivider'));
  final workspace = find.byKey(const Key('dashboardWorkspaceSurface'));
  final railRect = tester.getRect(rail);
  final dividerRect = tester.getRect(divider);
  final workspaceRect = tester.getRect(workspace);
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
}
