import 'dart:ui' as ui;

import 'package:any_deck/features/screenshot/editor/controller/screenshot_edit_controller.dart';
import 'package:any_deck/features/screenshot/editor/model/screenshot_edit.dart';
import 'package:any_deck/features/screenshot/editor/widgets/screenshot_edit_overlay.dart';
import 'package:any_deck/features/screenshot/widgets/screenshot_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 原图点先随预览旋转，再由 Viewer 做缩放和平移，模拟真实全局鼠标位置。
Offset _scenePoint(Offset point, int rotation) => switch (rotation) {
  90 => Offset(160 - point.dy, point.dx),
  180 => Offset(100 - point.dx, 160 - point.dy),
  270 => Offset(point.dy, 100 - point.dx),
  _ => point,
};

Future<ui.Image> _source(WidgetTester tester) async =>
    (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.white, BlendMode.src);
      final picture = recorder.endRecording();
      try {
        return await picture.toImage(100, 160);
      } finally {
        picture.dispose();
      }
    }))!;

Widget _canvas(
  ProviderContainer container,
  ui.Image image,
  TransformationController transform,
  int rotation,
) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 30, top: 20),
          child: SizedBox(
            width: 400,
            height: 360,
            child: Consumer(
              builder: (context, ref, _) {
                final tool = ref.watch(
                  screenshotEditControllerProvider(
                    'overlay',
                  ).select((state) => state.tool),
                );
                return ScreenshotCanvas(
                  decodedImage: image,
                  rotationAngle: rotation,
                  transformationController: transform,
                  isLayoutAnalysis: false,
                  panEnabled: tool == ScreenshotEditTool.pan,
                  imageOverlay: ScreenshotEditOverlay(
                    sessionId: 'overlay',
                    source: image,
                    mosaicImage: null,
                    rotation: rotation,
                    busy: false,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  ),
);

Offset _globalPoint(
  WidgetTester tester,
  TransformationController transform,
  Offset sourcePoint,
  int rotation,
) {
  final viewport = tester.renderObject<RenderBox>(
    find.byType(ScreenshotCanvas),
  );
  return viewport.localToGlobal(
    MatrixUtils.transformPoint(
      transform.value,
      _scenePoint(sourcePoint, rotation),
    ),
  );
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(
    from,
    kind: ui.PointerDeviceKind.mouse,
  );
  await gesture.moveTo(Offset.lerp(from, to, 0.5)!);
  await gesture.moveTo(to);
  await gesture.up();
  await tester.pump();
}

void main() {
  for (final rotation in [0, 90, 180, 270]) {
    testWidgets('$rotation 度缩放和平移后标注保留原图坐标且不拖动画布', (tester) async {
      final image = await _source(tester);
      final transform = TransformationController();
      final container = ProviderContainer();
      addTearDown(image.dispose);
      addTearDown(transform.dispose);
      addTearDown(container.dispose);
      await tester.pumpWidget(_canvas(container, image, transform, rotation));
      await tester.pump();
      transform.value = Matrix4.identity()
        ..setTranslationRaw(70, 40, 0)
        ..scaleByDouble(1.5, 1.5, 1, 1);
      await tester.pump();
      final before = List<double>.of(transform.value.storage);
      await _drag(
        tester,
        _globalPoint(tester, transform, const Offset(15, 25), rotation),
        _globalPoint(tester, transform, const Offset(70, 110), rotation),
      );
      final state = container.read(screenshotEditControllerProvider('overlay'));
      expect(state.marks, hasLength(1));
      expect(state.marks.single.points.first.dx, closeTo(15, 0.001));
      expect(state.marks.single.points.first.dy, closeTo(25, 0.001));
      expect(state.marks.single.points.last.dx, closeTo(70, 0.001));
      expect(state.marks.single.points.last.dy, closeTo(110, 0.001));
      expect(transform.value.storage, orderedEquals(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('拖动画布工具交回 Viewer 手势且不新增标注', (tester) async {
    final image = await _source(tester);
    final transform = TransformationController();
    final container = ProviderContainer();
    addTearDown(image.dispose);
    addTearDown(transform.dispose);
    addTearDown(container.dispose);
    await tester.pumpWidget(_canvas(container, image, transform, 0));
    await tester.pump();
    transform.value = Matrix4.identity()
      ..setTranslationRaw(70, 40, 0)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    container
        .read(screenshotEditControllerProvider('overlay').notifier)
        .selectTool(ScreenshotEditTool.pan);
    await tester.pump();
    final previous = transform.value.getTranslation();
    final start = _globalPoint(tester, transform, const Offset(35, 60), 0);
    await _drag(tester, start, start + const Offset(50, 30));
    expect(
      container.read(screenshotEditControllerProvider('overlay')).marks,
      isEmpty,
    );
    final next = transform.value.getTranslation();
    expect(next.x, greaterThan(previous.x));
    expect(next.y, greaterThan(previous.y));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('起点必须在图片内，拖动越界时末点裁剪到原图边缘', (tester) async {
    final image = await _source(tester);
    final transform = TransformationController();
    final container = ProviderContainer();
    addTearDown(image.dispose);
    addTearDown(transform.dispose);
    addTearDown(container.dispose);
    await tester.pumpWidget(_canvas(container, image, transform, 0));
    await tester.pump();
    transform.value = Matrix4.identity()
      ..setTranslationRaw(70, 40, 0)
      ..scaleByDouble(1.5, 1.5, 1, 1);
    await tester.pump();
    await _drag(
      tester,
      _globalPoint(tester, transform, const Offset(-10, 30), 0),
      _globalPoint(tester, transform, const Offset(60, 80), 0),
    );
    expect(
      container.read(screenshotEditControllerProvider('overlay')).marks,
      isEmpty,
    );
    await _drag(
      tester,
      _globalPoint(tester, transform, const Offset(30, 50), 0),
      _globalPoint(tester, transform, const Offset(130, 180), 0),
    );
    final mark = container
        .read(screenshotEditControllerProvider('overlay'))
        .marks
        .single;
    expect(mark.points.last, const Offset(100, 160));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
