import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:any_deck/features/screenshot/editor/controller/screenshot_edit_controller.dart';
import 'package:any_deck/features/screenshot/editor/model/screenshot_edit.dart';
import 'package:any_deck/features/screenshot/editor/renderer/screenshot_edit_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _image(
  int width,
  int height,
  void Function(Canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _pixels(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawRgba,
))!.buffer.asUint8List();

List<int> _pixel(Uint8List bytes, int width, int x, int y) =>
    bytes.sublist((y * width + x) * 4, (y * width + x) * 4 + 4);

ScreenshotEditMark _mark(
  ScreenshotEditTool tool,
  List<Offset> points, {
  Color color = Colors.red,
  double width = 6,
}) =>
    ScreenshotEditMark(tool: tool, points: points, color: color, width: width);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('截图编辑操作历史', () {
    late ProviderContainer container;
    late ScreenshotEditController controller;
    final provider = screenshotEditControllerProvider('test');

    setUp(() {
      container = ProviderContainer();
      container.listen(provider, (_, _) {});
      controller = container.read(provider.notifier);
    });
    tearDown(() => container.dispose());

    void draw([double y = 20]) {
      controller.begin(const Offset(10, 10));
      controller.update(Offset(30, y));
      controller.end();
    }

    test('一次完整落笔作为一次撤销，重做恢复，新笔迹清空重做', () {
      draw();
      draw(30);
      expect(container.read(provider).marks, hasLength(2));
      controller.undo();
      expect(container.read(provider).marks, hasLength(1));
      expect(container.read(provider).canRedo, isTrue);
      controller.redo();
      expect(container.read(provider).marks, hasLength(2));
      draw(35);
      controller.undo();
      controller.undo();
      draw(40);
      expect(container.read(provider).canRedo, isFalse);
    });

    test('草稿取消和空形状不创建历史，pan 不产生标注', () {
      controller.begin(const Offset(10, 10));
      controller.end();
      expect(container.read(provider).isDirty, isFalse);
      controller.begin(const Offset(10, 10));
      controller.update(const Offset(20, 20));
      controller.cancelStroke();
      expect(container.read(provider).marks, isEmpty);
      expect(container.read(provider).draft, isNull);
      controller.selectTool(ScreenshotEditTool.pan);
      draw();
      expect(container.read(provider).isDirty, isFalse);
    });

    test('单击画笔保留圆点，多段轨迹整体撤销，马赛克默认使用可见笔宽', () {
      controller.selectTool(ScreenshotEditTool.pen);
      controller.begin(const Offset(10, 10));
      controller.end();
      expect(container.read(provider).marks.single.points, [
        const Offset(10, 10),
      ]);
      controller.begin(const Offset(20, 10));
      controller.update(const Offset(30, 10));
      controller.update(const Offset(30, 30));
      controller.end();
      expect(container.read(provider).marks.last.points, hasLength(3));
      controller.undo();
      expect(container.read(provider).marks, hasLength(1));
      controller.selectTool(ScreenshotEditTool.mosaic);
      expect(container.read(provider).width, 36);
      controller.setWidth(60);
      controller.selectTool(ScreenshotEditTool.mosaic);
      expect(container.read(provider).width, 60);
      controller.selectTool(ScreenshotEditTool.rectangle);
      expect(container.read(provider).width, 60);
    });

    test('样式在落笔时固定，并且会话之间互不影响', () {
      controller.begin(const Offset(10, 10));
      controller.setColor(Colors.blue);
      controller.setWidth(18);
      controller.update(const Offset(20, 20));
      controller.end();
      final mark = container.read(provider).marks.single;
      expect(mark.color, Colors.red);
      expect(mark.width, 6);
      expect(
        container.read(screenshotEditControllerProvider('another')).marks,
        isEmpty,
      );
      expect(() => mark.points.add(Offset.zero), throwsUnsupportedError);
    });

    test('很长的轨迹保留首尾且有采样上限，历史也有数量上限', () {
      controller.selectTool(ScreenshotEditTool.pen);
      controller.begin(Offset.zero);
      for (var i = 1; i <= 6000; i++) {
        controller.update(Offset(i.toDouble(), 10));
      }
      controller.end();
      final mark = container.read(provider).marks.single;
      expect(
        mark.points.length,
        lessThanOrEqualTo(ScreenshotEditController.maxPointsPerMark),
      );
      expect(mark.points.first, Offset.zero);
      expect(mark.points.last, const Offset(6000, 10));
      for (var i = 0; i < ScreenshotEditController.maxMarks + 2; i++) {
        draw();
      }
      expect(
        container.read(provider).marks,
        hasLength(ScreenshotEditController.maxMarks),
      );
    });
  });

  test('矩形、椭圆、画笔与实色遮盖合成原尺寸 PNG，原图像素保持不变', () async {
    final source = await _image(80, 80, (canvas) {
      canvas.drawColor(Colors.white, BlendMode.src);
    });
    addTearDown(source.dispose);
    final before = await _pixels(source);
    final result = await ScreenshotEditRenderer.render(source, [
      _mark(ScreenshotEditTool.rectangle, [
        const Offset(5, 5),
        const Offset(25, 25),
      ]),
      _mark(ScreenshotEditTool.ellipse, [
        const Offset(35, 5),
        const Offset(55, 25),
      ]),
      _mark(ScreenshotEditTool.pen, [
        const Offset(5, 40),
        const Offset(25, 40),
      ]),
      _mark(ScreenshotEditTool.cover, [
        const Offset(35, 35),
        const Offset(55, 55),
      ], color: Colors.blue.withValues(alpha: 0.1)),
    ]);
    addTearDown(result.image.dispose);
    expect(result.image.width, 80);
    expect(result.image.height, 80);
    final pixels = await _pixels(result.image);
    expect(_pixel(pixels, 80, 5, 15), [244, 67, 54, 255]);
    expect(_pixel(pixels, 80, 15, 15), [255, 255, 255, 255]);
    expect(_pixel(pixels, 80, 45, 5).first, 244);
    expect(_pixel(pixels, 80, 15, 40), [244, 67, 54, 255]);
    expect(_pixel(pixels, 80, 45, 45), [33, 150, 243, 255]);
    expect(await _pixels(source), before);
    final codec = await ui.instantiateImageCodec(result.bytes);
    try {
      final decoded = (await codec.getNextFrame()).image;
      expect(decoded.width, 80);
      expect(decoded.height, 80);
      decoded.dispose();
    } finally {
      codec.dispose();
    }
  });

  test('马赛克沿笔迹覆盖且没有蒙版接缝，笔迹外像素保持原样', () async {
    final source = await _image(72, 72, (canvas) {
      for (var x = 0; x < 72; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), 0, 1, 72),
          Paint()..color = x.isEven ? Colors.white : Colors.black,
        );
      }
    });
    addTearDown(source.dispose);
    final mosaic = await ScreenshotEditRenderer.createMosaic(source);
    addTearDown(mosaic.dispose);
    expect(mosaic.width, 4);
    expect(mosaic.height, 4);
    final result = await ScreenshotEditRenderer.render(source, [
      _mark(ScreenshotEditTool.mosaic, [
        const Offset(15, 36),
        const Offset(36, 36),
        const Offset(57, 36),
      ], width: 20),
    ], mosaicImage: mosaic);
    addTearDown(result.image.dispose);
    final original = await _pixels(source);
    final pixels = await _pixels(result.image);
    expect(_pixel(pixels, 72, 20, 10), _pixel(original, 72, 20, 10));
    // 低分辨率纹理将高频黑白条纹平均，圆端点与连接矩形的重叠处也必须覆盖。
    for (var x = 15; x <= 57; x++) {
      final value = _pixel(pixels, 72, x, 36).first;
      expect(value, inInclusiveRange(100, 155), reason: 'x=$x');
    }
  });

  test('单点与转角画笔可导出，缺省马赛克缓存自动生成并释放', () async {
    final source = await _image(72, 72, (canvas) {
      canvas.drawColor(Colors.white, BlendMode.src);
    });
    addTearDown(source.dispose);
    final result = await ScreenshotEditRenderer.render(source, [
      _mark(ScreenshotEditTool.pen, [const Offset(10, 10)]),
      _mark(ScreenshotEditTool.pen, [
        const Offset(20, 10),
        const Offset(30, 10),
        const Offset(30, 30),
      ]),
      _mark(ScreenshotEditTool.mosaic, [const Offset(55, 55)], width: 12),
    ]);
    addTearDown(result.image.dispose);
    final pixels = await _pixels(result.image);
    for (final point in [
      const Offset(10, 10),
      const Offset(25, 10),
      const Offset(30, 25),
    ]) {
      expect(_pixel(pixels, 72, point.dx.toInt(), point.dy.toInt()), [
        244,
        67,
        54,
        255,
      ]);
    }
    expect(_pixel(pixels, 72, 25, 25), [255, 255, 255, 255]);
    expect(_pixel(pixels, 72, 55, 55), [255, 255, 255, 255]);
    // 再次使用同一原图导出，验证内部缓存回收不会释放调用方持有的 source。
    final next = await ScreenshotEditRenderer.render(source, []);
    addTearDown(next.image.dispose);
    expect(next.image.width, 72);
  });
}
