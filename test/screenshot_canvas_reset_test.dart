import 'dart:ui' as ui;

import 'package:any_deck/features/screenshot/widgets/screenshot_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _createImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.blue,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

void main() {
  testWidgets('重置恢复图片初始适配大小和居中位置', (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final image = await _createImage(100, 200);
    final transformationController = TransformationController();
    final canvasKey = GlobalKey<ScreenshotCanvasState>();
    addTearDown(image.dispose);
    addTearDown(transformationController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              height: 300,
              child: ScreenshotCanvas(
                key: canvasKey,
                decodedImage: image,
                rotationAngle: 0,
                transformationController: transformationController,
                isLayoutAnalysis: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final initialScale = transformationController.value.getMaxScaleOnAxis();
    final initialTranslation = transformationController.value.getTranslation();
    expect(initialScale, closeTo(1.5, 0.001));
    expect(initialTranslation.x, closeTo(125, 0.001));
    expect(initialTranslation.y, closeTo(0, 0.001));

    transformationController.value = Matrix4.identity()
      ..setTranslationRaw(20, 40, 0)
      // ignore: deprecated_member_use
      ..scale(3.0);
    canvasKey.currentState!.resetZoomAndPan();

    final resetScale = transformationController.value.getMaxScaleOnAxis();
    final resetTranslation = transformationController.value.getTranslation();
    expect(resetScale, closeTo(initialScale, 0.001));
    expect(resetTranslation.x, closeTo(initialTranslation.x, 0.001));
    expect(resetTranslation.y, closeTo(initialTranslation.y, 0.001));
  });
}
