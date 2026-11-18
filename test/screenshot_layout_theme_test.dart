import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:any_deck/app/l10n/app_localizations.dart';
import 'package:any_deck/app/theme/app_theme.dart';
import 'package:any_deck/core/adb/discovered_device.dart';
import 'package:any_deck/core/layout_inspector/layout_node.dart';
import 'package:any_deck/features/layout/layout_hierarchy_tree.dart';
import 'package:any_deck/features/layout/layout_screen_preview.dart';
import 'package:any_deck/features/screenshot/model/screenshot_state.dart';
import 'package:any_deck/features/screenshot/widgets/screenshot_canvas.dart';
import 'package:any_deck/features/screenshot/widgets/screenshot_toolbar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// 使用真实主题与本地化，动态换色时保留页面组件和选择状态。
Widget _app(Widget child, Brightness brightness, AppThemeColor color) =>
    MaterialApp(
      theme: buildAppTheme(brightness, themeColor: color),
      themeAnimationDuration: Duration.zero,
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(body: child),
    );

Future<ui.Image> _whiteImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.white, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}

/// 对实际 Widget 注入的 Painter 采样选区边框，验证颜色真正进入绘制流程。
Future<Color> _selectionPixel(CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size(100, 100));
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  const offset = (30 * 100 + 10) * 4;
  final color = Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
  image.dispose();
  picture.dispose();
  return color;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} 截图连续保存按钮跟随换色且保留点击回调', (tester) async {
      var toggles = 0;
      final toolbar = ScreenshotToolbar(
        device: const DiscoveredDevice(id: 'phone', status: 'device'),
        state: ScreenshotLayoutState(
          rawScreenshotBytes: Uint8List.fromList([1]),
          isAutoRefresh: true,
          isAutoSave: true,
        ),
        onRefresh: () {},
        onSave: () {},
        onCopy: () {},
        onRotateLeft: () {},
        onRotateRight: () {},
        onToggleAutoRefresh: () => toggles++,
        onStartRecording: () {},
        onStopRecording: () {},
        onToggleLayoutAnalysis: (_) {},
        onShowPropertiesChanged: (_) {},
      );
      for (final color in [AppThemeColor.blue, AppThemeColor.purple]) {
        await tester.pumpWidget(_app(toolbar, brightness, color));
        await tester.pumpAndSettle();
        final button = find.byIcon(CupertinoIcons.clock_fill);
        expect(tester.widget<Icon>(button).color, color.color);
        await tester.tap(button);
        await tester.pump();
      }
      expect(toggles, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${brightness.name} 布局树点击选中后保留选择并更新主题背景', (tester) async {
      final root = LayoutNode({
        'class': 'android.widget.TextView',
        'text': '主题节点',
        'bounds': '[10,10][60,60]',
      });
      final selected = ValueNotifier<LayoutNode?>(null);
      addTearDown(selected.dispose);
      final tree = ValueListenableBuilder<LayoutNode?>(
        valueListenable: selected,
        builder: (_, value, _) => LayoutHierarchyTree(
          rootNode: root,
          selectedNode: value,
          expandedNodes: {root},
          onNodeSelected: (node) => selected.value = node,
          onNodeHovered: (_) {},
          onNodeExpansionChanged: (_, _) {},
        ),
      );
      final nodeText = find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('主题节点'),
      );
      await tester.pumpWidget(_app(tree, brightness, AppThemeColor.blue));
      await tester.tap(nodeText);
      await tester.pumpAndSettle();
      expect(selected.value, same(root));
      for (final color in [AppThemeColor.blue, AppThemeColor.purple]) {
        await tester.pumpWidget(_app(tree, brightness, color));
        await tester.pumpAndSettle();
        final selectedRow = tester.widget<Container>(
          find.ancestor(of: nodeText, matching: find.byType(Container)).first,
        );
        expect(
          (selectedRow.decoration! as BoxDecoration).color,
          color.color.withValues(alpha: 0.18),
        );
        expect(selected.value, same(root));
      }
      expect(tester.takeException(), isNull);
    });

    for (final standaloneLayout in [false, true]) {
      testWidgets(
        '${brightness.name} ${standaloneLayout ? '布局' : '截图'}画布换色重绘真实选区',
        (tester) async {
          final image = (await tester.runAsync(_whiteImage))!;
          final transform = TransformationController();
          addTearDown(image.dispose);
          addTearDown(transform.dispose);
          final node = LayoutNode({'bounds': '[10,10][60,60]'});
          final Widget preview = standaloneLayout
              ? LayoutScreenPreview(
                  decodedImage: image,
                  selectedNode: node,
                  hoveredNode: null,
                  showBorders: false,
                  rotationAngle: 0,
                  transformationController: transform,
                  onNodeSelected: (_) {},
                  onNodeHovered: (_) {},
                  onViewportSizeChanged: (_) {},
                  enableClickSelect: false,
                  useDp: false,
                  deviceScale: 1,
                )
              : ScreenshotCanvas(
                  decodedImage: image,
                  selectedNode: node,
                  rotationAngle: 0,
                  transformationController: transform,
                  isLayoutAnalysis: true,
                );
          CustomPainter? previous;
          for (final color in [AppThemeColor.blue, AppThemeColor.purple]) {
            await tester.pumpWidget(_app(preview, brightness, color));
            await tester.pumpAndSettle();
            final paint = tester.widget<CustomPaint>(
              find.byWidgetPredicate(
                (widget) => widget is CustomPaint && widget.painter != null,
              ),
            );
            final painter = paint.painter!;
            expect(
              await tester.runAsync(() => _selectionPixel(painter)),
              color.color,
            );
            if (previous != null) {
              expect(painter.shouldRepaint(previous), isTrue);
            }
            previous = painter;
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
